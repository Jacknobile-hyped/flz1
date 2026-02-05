import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<String>? suggestedQuestions;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.suggestedQuestions,
  });
}

class AnalysisSection {
  final String title;
  final String content;

  AnalysisSection(this.title, this.content);
}

class ChatGptService {
  static const String apiKey = '';
  static const String apiUrl = 'https://api.openai.com/v1/chat/completions';

  // Funzione per calcolare i token utilizzati
  int _calculateTokens(String text) {
    return (text.length / 4).ceil();
  }

  // Funzione per verificare i limiti dei token
  Future<bool> _checkTokenLimits({
    required String userId,
    required int estimatedTokens,
    required bool isPremium,
  }) async {
    try {
      if (isPremium) {
        return true;
      }
      
      final databaseRef = FirebaseDatabase.instance.ref();
      const int dailyTokenLimit = 3000;
      
      final today = DateTime.now().toIso8601String().split('T')[0];
      final dailyUsagePath = 'users/users/$userId/daily_token_usage/$today';
      final dailySnapshot = await databaseRef.child(dailyUsagePath).get();
      
      int dailyTokens = 0;
      if (dailySnapshot.exists) {
        final dailyData = Map<String, dynamic>.from(dailySnapshot.value as Map<dynamic, dynamic>);
        dailyTokens = dailyData['tokens_used'] ?? 0;
      }
      
      if (dailyTokens + estimatedTokens > dailyTokenLimit) {
        print('[TOKENS] ❌ Limite giornaliero superato: $dailyTokens + $estimatedTokens > $dailyTokenLimit');
        return false;
      }
      
      return true;
    } catch (e) {
      print('[TOKENS] ❌ Errore nel controllo limiti token: $e');
      return false;
    }
  }

  // Funzione per salvare i token utilizzati nel database Firebase
  Future<void> _saveTokenUsage({
    required String userId,
    required String videoId,
    required int promptTokens,
    required int completionTokens,
    required int totalTokens,
    required String analysisType,
  }) async {
    try {
      final databaseRef = FirebaseDatabase.instance.ref();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      final tokenPath = 'users/users/$userId/token_usage/$videoId/$timestamp';
      
      final tokenData = {
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'total_tokens': totalTokens,
        'analysis_type': analysisType,
        'timestamp': timestamp,
        'date': DateTime.now().toIso8601String(),
      };
      
      await databaseRef.child(tokenPath).set(tokenData);
      
      final userTotalsPath = 'users/users/$userId/token_totals';
      final totalsSnapshot = await databaseRef.child(userTotalsPath).get();
      
      Map<String, dynamic> currentTotals = {};
      if (totalsSnapshot.exists) {
        currentTotals = Map<String, dynamic>.from(totalsSnapshot.value as Map<dynamic, dynamic>);
      }
      
      final updatedTotals = {
        'total_tokens_used': (currentTotals['total_tokens_used'] ?? 0) + totalTokens,
        'total_analyses': (currentTotals['total_analyses'] ?? 0) + 1,
        'last_updated': timestamp,
      };
      
      await databaseRef.child(userTotalsPath).update(updatedTotals);
      
      final today = DateTime.now().toIso8601String().split('T')[0];
      final dailyUsagePath = 'users/users/$userId/daily_token_usage/$today';
      final dailySnapshot = await databaseRef.child(dailyUsagePath).get();
      
      Map<String, dynamic> currentDaily = {};
      if (dailySnapshot.exists) {
        currentDaily = Map<String, dynamic>.from(dailySnapshot.value as Map<dynamic, dynamic>);
      }
      
      final updatedDaily = {
        'tokens_used': (currentDaily['tokens_used'] ?? 0) + totalTokens,
        'analyses_count': (currentDaily['analyses_count'] ?? 0) + 1,
        'date': today,
        'last_updated': timestamp,
      };
      
      await databaseRef.child(dailyUsagePath).set(updatedDaily);
      
      print('[TOKENS] ✅ Token usage salvati: $totalTokens tokens per $analysisType analysis');
    } catch (e) {
      print('[TOKENS] ❌ Errore nel salvataggio token usage: $e');
    }
  }

  Future<String> analyzeVideoStats(
    Map<String, dynamic> video,
    Map<String, Map<String, double>> statsData,
    String language,
    [Map<String, Map<String, dynamic>>? accountMeta,
     Map<String, Map<String, int>>? manualStats,
     String? customPrompt,
     String? analysisType = 'initial',
     bool isPremium = false]
  ) async {
    try {
      String prompt = customPrompt ?? _buildPrompt(video, statsData, language, accountMeta, manualStats);
      
      final promptTokens = _calculateTokens(prompt);
      final estimatedTotalTokens = promptTokens + 1000;
      
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !isPremium) {
        final canProceed = await _checkTokenLimits(
          userId: user.uid,
          estimatedTokens: estimatedTotalTokens,
          isPremium: isPremium,
        );
        
        if (!canProceed) {
          throw Exception('Token limit exceeded. Please upgrade to premium or wait until tomorrow.');
        }
      }
      
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
        
        final completionTokens = _calculateTokens(completion);
        final totalTokens = promptTokens + completionTokens;
        
        final user = FirebaseAuth.instance.currentUser;
        final videoId = video['id']?.toString() ?? video['key']?.toString();
        
        if (user != null && videoId != null && !isPremium) {
          await _saveTokenUsage(
            userId: user.uid,
            videoId: videoId,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            analysisType: analysisType ?? 'initial',
          );
        }
        
        print('[AI] ✅ Analisi completata: $totalTokens tokens utilizzati ($promptTokens prompt + $completionTokens completion)');
        
        return completion;
      } else {
        throw Exception('Failed to get AI analysis: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error analyzing video stats: $e');
    }
  }

  String _buildPrompt(
    Map<String, dynamic> video,
    Map<String, Map<String, double>> statsData,
    String language,
    [Map<String, Map<String, dynamic>>? accountMeta,
     Map<String, Map<String, int>>? manualStats]
  ) {
    String publishDate = 'N/A';
    DateTime? date;
    
    if (video['publish_date'] != null) {
      try {
        date = DateTime.parse(video['publish_date']);
        publishDate = DateFormat('yyyy-MM-dd HH:mm').format(date);
      } catch (e) {
        publishDate = video['publish_date'].toString();
      }
    } else if (video['date'] != null) {
      publishDate = video['date'].toString();
      try {
        final parsedDate = DateFormat('dd/MM/yyyy HH:mm').parse(publishDate);
        date = parsedDate;
        publishDate = DateFormat('yyyy-MM-dd HH:mm').format(parsedDate);
      } catch (e) {}
    }

    String timeAgo = 'N/A';
    if (date != null) {
      final now = DateTime.now();
      final difference = now.difference(date);
      if (difference.inDays > 0) {
        timeAgo = '${difference.inDays} giorni fa';
      } else if (difference.inHours > 0) {
        timeAgo = '${difference.inHours} ore fa';
      } else {
        timeAgo = '${difference.inMinutes} minuti fa';
      }
    }

    String generalDescription = video['description'] ?? 'Non disponibile';

    final now = DateTime.now();
    final nowMinutes = now.millisecondsSinceEpoch ~/ 60000;
    final nowFormatted = DateFormat('yyyy-MM-dd HH:mm').format(now);

    String prompt = '''
IMPORTANT: Answer EXCLUSIVELY and MANDATORILY in the following language: "$language".

Objective: Analyze video performance using the data provided (date and time of publication, likes, views, comments), broken down by social platform.

Don't give generic advice: evaluate the data analytically, identifying patterns, anomalies, weaknesses, and strengths. Compare content, timing, and platforms. Focus on the actual effectiveness of the content posted, deducing what works and what doesn't.

Follow this precise structure:

Analyze how date and time affect performance (highlight times or days that bring better or worse results).

Compare performance across different platforms: highlight which content performs best where and why.

Evaluate the strengths of the content based on actual engagement (like/view ratio, comment/view ratio, etc.).

Identify specific weaknesses: where traffic is lost, what does not generate interactions, differences between similar content

Suggest concrete and specific improvements for each platform: what to change in content, style, timing, or format

Propose precise future publishing strategies based on historical data (e.g., "between 6 and 8 p.m. on Instagram brings twice as many comments as other times")

Bonus: indicate at least one little-known trick to improve visibility on each platform, relevant to the content analyzed

IMPORTANT:

DO NOT start with introductory phrases such as "Here is the analysis"

DO NOT include generic comments such as "consistency is important" or "use relevant hashtags"

Write in short paragraphs, visually separated for easy reading

Use bullet points where useful

End with: "Note: This AI analysis is based on available data and trends. Results may vary based on algorithm changes and other factors."

Do not confuse twitter with threads (sometimes you confuse twitter with threads)

IMPORTANT: After your analysis, provide exactly 3 follow-up questions that users might want to ask about this analysis. Format them as:
SUGGESTED_QUESTIONS:
1. [First question]
2. [Second question] 
3. [Third question]

These questions should be relevant to the analysis and help users dive deeper into specific aspects.
''';

    prompt += '\n\nVideo details:';
    prompt += '\nTitle: \'${video['title'] ?? 'Non disponibile'}\'';
    prompt += '\nDescription: $generalDescription';
    prompt += '\nPublish date and time: $publishDate ($timeAgo)';
    prompt += '\nCurrent date and time: $nowFormatted (minutes since epoch: $nowMinutes)';
    prompt += '\n';

    Map<String, List<String>> platformAccounts = {};
    statsData.forEach((metric, platforms) {
      platforms.forEach((accountKey, value) {
        String platform = '';
        final lower = accountKey.toLowerCase();
        if (lower.startsWith('tiktok')) platform = 'tiktok';
        else if (lower.startsWith('youtube')) platform = 'youtube';
        else if (lower.startsWith('instagram')) platform = 'instagram';
        else if (lower.startsWith('facebook')) platform = 'facebook';
        else if (lower.startsWith('threads')) platform = 'threads';
        else if (lower.startsWith('twitter')) platform = 'twitter';
        if (platform.isNotEmpty) {
          platformAccounts.putIfAbsent(platform, () => <String>[]);
          if (!platformAccounts[platform]!.contains(accountKey)) {
            platformAccounts[platform]!.add(accountKey);
          }
        }
      });
    });

    final orderedPlatforms = [
      'tiktok', 'youtube', 'instagram', 'facebook', 'threads', 'twitter'
    ].where((p) => platformAccounts.containsKey(p)).toList();

    for (final platform in orderedPlatforms) {
      prompt += '\n\n$platform:';
      final accounts = platformAccounts[platform]!;
      accounts.sort((a, b) {
        String metaA = a;
        String metaB = b;
        if (accountMeta != null) {
          final displayA = accountMeta[a]?['display_name'];
          final displayB = accountMeta[b]?['display_name'];
          if (displayA != null && displayA.toString().isNotEmpty) metaA = displayA.toString();
          if (displayB != null && displayB.toString().isNotEmpty) metaB = displayB.toString();
        }
        return metaA.compareTo(metaB);
      });
      for (final accountKey in accounts) {
        final meta = accountMeta != null ? accountMeta[accountKey] : null;
        final displayName = meta?['display_name'] ?? accountKey;
        final username = meta?['username'] ?? '';
        final description = meta?['description'] ?? '';
        final followers = meta?['followers_count'] ?? 0;
        final platformType = (meta?['platform'] ?? '').toString().toLowerCase();
        final isIGNoToken = platformType == 'instagram' && manualStats != null && manualStats[accountKey] != null;
        prompt += '\n  Account: $displayName';
        if (username != '') prompt += ' (username: $username)';
        if (description != '') prompt += '\n    Description: $description';
        if (followers != 0) prompt += '\n    Followers: $followers';
        for (final metric in ['likes', 'views', 'comments']) {
          double? value;
          if (isIGNoToken) {
            value = manualStats![accountKey]?[metric]?.toDouble() ?? 0;
          } else if (metric == 'views' && accountMeta != null) {
            if ((platformType == 'instagram' || platformType == 'facebook' || platformType == 'threads') && manualStats != null && manualStats[accountKey]?['views'] != null) {
              value = manualStats[accountKey]?['views']?.toDouble() ?? 0;
            } else {
              value = statsData[metric]?[accountKey];
            }
          } else {
            value = statsData[metric]?[accountKey];
          }
          if (value != null) {
            prompt += '\n    $metric: \u001b[1m${value.toInt()}\u001b[0m';
          }
        }
      }
    }

    return prompt;
  }
}

class _AIAnalysisPageState extends State<AIAnalysisPage> {
  final ChatGptService _chatGptService = ChatGptService();
  bool _isAnalyzing = false;
  bool _isPremium = false;
  bool _hasUsedTrial = false;
  bool _hasDailyAnalysisAvailable = true;
  final ValueNotifier<String?> _analysisNotifier = ValueNotifier<String?>(null);
  
  // Chat variables
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final ScrollController _chatScrollController = ScrollController();
  List<ChatMessage> _chatMessages = [];
  bool _isChatLoading = false;
  Map<int, bool> _aiMessageLikes = {};
  Map<int, bool> _aiMessageDislikes = {};
  final ValueNotifier<int> _feedbackUpdateNotifier = ValueNotifier<int>(0);
  Timer? _feedbackTimer;
  String? _userProfileImageUrl;
  
  // Analysis variables
  String? _lastAnalysis;
  int? _lastAnalysisTimestampMinutes;
  String? _errorMessage;
  String _language = 'Italian';

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
    _loadHasUsedTrial();
    _loadDailyAnalysisStatus();
    _loadUserProfileImage();
    _loadChatGptAnalysis();
    _loadChatMessagesFromFirebase();
    _initializeChatMessagesStream();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatFocusNode.dispose();
    _chatScrollController.dispose();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  // Check if the user is premium
  Future<void> _checkPremiumStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final snapshot = await databaseRef.child('users').child('users').child(user.uid).child('isPremium').get();
        setState(() {
          _isPremium = (snapshot.value as bool?) ?? false;
        });
      }
    } catch (e) {
      print('Error checking premium status: $e');
    }
  }

  // Load trial status
  Future<void> _loadHasUsedTrial() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final database = FirebaseDatabase.instance.ref();
        final userRef = database.child('users/users/${user.uid}');
        final snapshot = await userRef.get();
        if (snapshot.exists) {
          final userData = snapshot.value as Map<dynamic, dynamic>;
          setState(() {
            _hasUsedTrial = userData['has_used_trial'] == true;
          });
        }
      }
    } catch (e) {
      print('Errore nel caricamento del trial: $e');
    }
  }

  // Load daily analysis status
  Future<void> _loadDailyAnalysisStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final today = DateTime.now().toIso8601String().split('T')[0];
        
        final dailyStatsRef = databaseRef.child('users').child('users').child(user.uid).child('daily_analysis_stats');
        final todayRef = dailyStatsRef.child(today);
        
        final snapshot = await todayRef.get();
        
        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          final analysisCount = data['analysis_count'] as int? ?? 0;
          setState(() {
            _hasDailyAnalysisAvailable = analysisCount < 1;
          });
        } else {
          setState(() {
            _hasDailyAnalysisAvailable = true;
          });
        }
      }
    } catch (e) {
      print('Errore nel caricamento dello stato analisi giornaliere: $e');
      setState(() {
        _hasDailyAnalysisAvailable = false;
      });
    }
  }

  // Load user profile image
  Future<void> _loadUserProfileImage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final snapshot = await databaseRef.child('users').child('users').child(user.uid).child('profile').child('profileImageUrl').get();
        if (snapshot.exists && snapshot.value is String) {
          setState(() {
            _userProfileImageUrl = snapshot.value as String;
          });
        }
      }
    } catch (e) {
      print('Error loading user profile image: $e');
    }
  }

  // Load ChatGPT analysis
  Future<void> _loadChatGptAnalysis() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
      if (user != null && videoId != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final snapshot = await databaseRef.child('users').child('users').child(user.uid).child('videos').child(videoId).child('chatgpt').get();
        if (snapshot.exists) {
          if (snapshot.value is String) {
            setState(() {
              _lastAnalysis = _fixEncoding(snapshot.value as String);
              _lastAnalysisTimestampMinutes = null;
            });
          } else if (snapshot.value is Map) {
            final map = Map<String, dynamic>.from(snapshot.value as Map);
            final text = map['text'] != null ? _fixEncoding(map['text'] as String) : null;
            final timestampMinutes = map['timestamp_minutes'] is int ? map['timestamp_minutes'] as int : int.tryParse(map['timestamp_minutes']?.toString() ?? '');
            
            List<String>? suggestedQuestions;
            if (map['suggested_questions'] != null && map['suggested_questions'] is List) {
              suggestedQuestions = (map['suggested_questions'] as List).cast<String>().map((q) => _fixEncoding(q)).toList();
            }
            
            setState(() {
              _lastAnalysis = text;
              _lastAnalysisTimestampMinutes = timestampMinutes;
              
              if (text != null) {
                _chatMessages.removeWhere((msg) => !msg.isUser && msg.text == text);
                
                _chatMessages.add(ChatMessage(
                  text: text,
                  isUser: false,
                  timestamp: DateTime.now(),
                  suggestedQuestions: suggestedQuestions,
                ));
              }
            });
          }
        }
      }
    } catch (e) {
      print('Errore caricamento chatgpt analysis da Firebase: $e');
    }
  }

  // Load chat messages from Firebase
  Future<void> _loadChatMessagesFromFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
      if (user != null && videoId != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final chatPath = 'users/users/${user.uid}/videos/$videoId/chat_messages';
        final snapshot = await databaseRef.child(chatPath).get();
        
        if (snapshot.exists) {
          final messagesData = snapshot.value as List<dynamic>?;
          if (messagesData != null) {
            List<ChatMessage> messages = [];
            for (final messageData in messagesData) {
              if (messageData is Map) {
                final data = Map<String, dynamic>.from(messageData);
                
                List<String>? suggestedQuestions;
                if (data['suggestedQuestions'] != null && data['suggestedQuestions'] is List) {
                  suggestedQuestions = (data['suggestedQuestions'] as List).cast<String>().map((q) => _fixEncoding(q)).toList();
                }
                
                messages.add(ChatMessage(
                  text: _fixEncoding(data['text'] ?? ''),
                  isUser: data['isUser'] ?? false,
                  timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] ?? 0),
                  suggestedQuestions: suggestedQuestions,
                ));
              }
            }
            setState(() {
              _chatMessages = messages;
            });
          }
        }
      }
    } catch (e) {
      print('Errore caricamento messaggi chat da Firebase: $e');
    }
  }

  // Initialize chat messages stream
  void _initializeChatMessagesStream() {
    // Implementation for real-time chat updates
  }

  // Fix encoding issues
  String _fixEncoding(String text) {
    return text.replaceAll('\\u001b[1m', '').replaceAll('\\u001b[0m', '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(
              Icons.psychology,
              color: const Color(0xFF6C63FF),
            ),
            const SizedBox(width: 8),
            Text(
              'AI Analysis',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.analytics_outlined,
              color: isDark ? Colors.white : Colors.black87,
            ),
            onPressed: _showTokenUsageStats,
          ),
        ],
      ),
      body: Column(
        children: [
          // Main content area
          Expanded(
            child: _lastAnalysis != null 
              ? _buildAnalysisContent()
              : _buildInitialAnalysisButton(),
          ),
        ],
      ),
    );
  }

  // Build initial analysis button
  Widget _buildInitialAnalysisButton() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.psychology,
                    size: 64,
                    color: const Color(0xFF6C63FF),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'AI Analysis',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Get detailed insights about your video performance across all platforms',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ElevatedButton(
                      onPressed: _isAnalyzing ? null : _analyzeWithAI,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isAnalyzing
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text('Analyzing...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          )
                        : Text('Analyze with AI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

  // Build analysis content
  Widget _buildAnalysisContent() {
    return Column(
      children: [
        // Analysis display area
        Expanded(
          child: ValueListenableBuilder<String?>(
            valueListenable: _analysisNotifier,
            builder: (context, analysis, child) {
              if (analysis == null) {
                return _buildAnalysisDisplay(_lastAnalysis!);
              }
              return _buildAnalysisDisplay(analysis);
            },
          ),
        ),
        
        // Chat input area
        _buildChatInput(),
      ],
    );
  }

  // Build analysis display
  Widget _buildAnalysisDisplay(String analysis) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Analysis content
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _formatAnalysisText(analysis, isDark, Theme.of(context)),
          ),
          
          const SizedBox(height: 16),
          
          // Chat messages
          if (_chatMessages.isNotEmpty) ...[
            Text(
              'Follow-up Questions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            _buildChatMessages(),
          ],
        ],
      ),
    );
  }

  // Build chat input
  Widget _buildChatInput() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              focusNode: _chatFocusNode,
              decoration: InputDecoration(
                hintText: 'Ask a follow-up question...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (_) => _sendChatMessage(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                Icons.send,
                color: Colors.white,
                size: 20,
              ),
              onPressed: _sendChatMessage,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build chat messages
  Widget _buildChatMessages() {
    return ListView.builder(
      controller: _chatScrollController,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _chatMessages.length + (_isChatLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _chatMessages.length && _isChatLoading) {
          return _buildAILoadingMessage();
        }
        return _buildChatMessage(_chatMessages[index], index);
      },
    );
  }

  // Analyze with AI
  Future<void> _analyzeWithAI() async {
    // Check token limits
    final hasReachedTokenLimit = await _checkTokenLimit();
    if (hasReachedTokenLimit) {
      _showDailyLimitReachedModal();
      return;
    }

    // Check time between analyses
    if (_lastAnalysisTimestampMinutes != null) {
      final nowMinutes = DateTime.now().millisecondsSinceEpoch ~/ 60000;
      final diff = nowMinutes - _lastAnalysisTimestampMinutes!;
      
      if (diff < 30) {
        final proceed = await _showTimeWarningDialog(diff);
        if (proceed != true) return;
      }
    }

    setState(() {
      _isAnalyzing = true;
    });

    try {
      final analysis = await _chatGptService.analyzeVideoStats(
        widget.video,
        widget.statsData,
        _language,
        widget.accountMeta,
        widget.manualStats,
        null,
        'initial',
        _isPremium,
      );

      final cleanAnalysis = _fixEncoding(analysis);
      final suggestedQuestions = _extractSuggestedQuestions(cleanAnalysis);
      final nowMinutes = DateTime.now().millisecondsSinceEpoch ~/ 60000;

      // Save to Firebase
      await _saveAnalysisToFirebase(cleanAnalysis, nowMinutes, suggestedQuestions);

      setState(() {
        _lastAnalysis = cleanAnalysis;
        _lastAnalysisTimestampMinutes = nowMinutes;
        _isAnalyzing = false;
      });

      _analysisNotifier.value = cleanAnalysis;

    } catch (e) {
      setState(() {
        _isAnalyzing = false;
      });

      if (e.toString().contains('Token limit exceeded')) {
        _showDailyLimitReachedModal();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Check token limit
  Future<bool> _checkTokenLimit() async {
    if (_isPremium) return false;
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final today = DateTime.now().toIso8601String().split('T')[0];
        final dailyUsagePath = 'users/users/${user.uid}/daily_token_usage/$today';
        final dailySnapshot = await databaseRef.child(dailyUsagePath).get();
        
        int dailyTokens = 0;
        if (dailySnapshot.exists) {
          final dailyData = Map<String, dynamic>.from(dailySnapshot.value as Map<dynamic, dynamic>);
          dailyTokens = dailyData['tokens_used'] ?? 0;
        }
        
        return dailyTokens >= 3000;
      }
    } catch (e) {
      print('Error checking token limit: $e');
    }
    return false;
  }

  // Show time warning dialog
  Future<bool?> _showTimeWarningDialog(int diff) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Wait at least 30 minutes'),
        content: Text('The last AI analysis was generated $diff minutes ago.\n\nFor the most effective results, it is recommended to wait at least 30 minutes between analyses.\n\nDo you want to continue anyway?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Continue'),
          ),
        ],
      ),
    );
  }

  // Show daily limit reached modal
  void _showDailyLimitReachedModal() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Daily Limit Reached'),
        content: Text('You have reached your daily AI analysis limit. Upgrade to premium for unlimited analyses.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  // Extract suggested questions
  List<String> _extractSuggestedQuestions(String analysis) {
    final questions = <String>[];
    final lines = analysis.split('\n');
    bool inQuestionsSection = false;
    
    for (final line in lines) {
      if (line.contains('SUGGESTED_QUESTIONS:')) {
        inQuestionsSection = true;
        continue;
      }
      
      if (inQuestionsSection && line.trim().isNotEmpty) {
        if (line.startsWith(RegExp(r'^\d+\.'))) {
          final question = line.replaceFirst(RegExp(r'^\d+\.\s*'), '').trim();
          if (question.isNotEmpty) {
            questions.add(question);
          }
        }
      }
      
      if (inQuestionsSection && questions.length >= 3) {
        break;
      }
    }
    
    return questions;
  }

  // Save analysis to Firebase
  Future<void> _saveAnalysisToFirebase(String analysis, int timestamp, List<String> suggestedQuestions) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
      if (user != null && videoId != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        await databaseRef.child('users').child('users').child(user.uid).child('videos').child(videoId).child('chatgpt').set({
          'text': analysis,
          'timestamp_minutes': timestamp,
          'suggested_questions': suggestedQuestions,
        });
      }
    } catch (e) {
      print('Errore salvataggio chatgpt analysis su Firebase: $e');
    }
  }

  // Send chat message
  Future<void> _sendChatMessage() async {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;

    // Check token limit
    final hasReachedTokenLimit = await _checkTokenLimit();
    if (hasReachedTokenLimit) {
      _showDailyLimitReachedModal();
      return;
    }

    // Add user message
    final userMessage = ChatMessage(
      text: message,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _chatMessages.add(userMessage);
      _isChatLoading = true;
    });

    _chatController.clear();
    _scrollToBottom();

    try {
      final chatPrompt = _buildChatPrompt(message, _language, widget.manualStats);
      final response = await _chatGptService.analyzeVideoStats(
        widget.video,
        widget.statsData,
        _language,
        widget.accountMeta,
        widget.manualStats,
        chatPrompt,
        'chat',
        _isPremium,
      );

      final aiMessage = ChatMessage(
        text: _fixEncoding(response),
        isUser: false,
        timestamp: DateTime.now(),
      );

      setState(() {
        _chatMessages.add(aiMessage);
        _isChatLoading = false;
      });

      _scrollToBottom();
      await _saveChatMessagesToFirebase();

    } catch (e) {
      setState(() {
        _isChatLoading = false;
      });

      if (e.toString().contains('Token limit exceeded')) {
        _showDailyLimitReachedModal();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Build chat prompt
  String _buildChatPrompt(String userMessage, String language, Map<String, int> manualStats) {
    return '''
IMPORTANT: Answer EXCLUSIVELY and MANDATORILY in the following language: "$language".

The user is asking a follow-up question about their video analysis. Please provide a detailed, helpful response based on the video data and previous analysis.

User question: $userMessage

Please provide a comprehensive answer that:
1. Directly addresses the user's question
2. Uses the video performance data to support your response
3. Provides actionable insights and recommendations
4. Maintains the same analytical style as the initial analysis

Answer in the same language as the question: $language
''';
  }

  // Scroll to bottom
  void _scrollToBottom() {
    if (_chatScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  // Save chat messages to Firebase
  Future<void> _saveChatMessagesToFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
      if (user != null && videoId != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final chatPath = 'users/users/${user.uid}/videos/$videoId/chat_messages';
        
        final messagesData = _chatMessages.map((msg) => {
          'text': msg.text,
          'isUser': msg.isUser,
          'timestamp': msg.timestamp.millisecondsSinceEpoch,
          'suggestedQuestions': msg.suggestedQuestions,
        }).toList();
        
        await databaseRef.child(chatPath).set(messagesData);
      }
    } catch (e) {
      print('Errore salvataggio messaggi chat su Firebase: $e');
    }
  }

  // Show token usage stats
  void _showTokenUsageStats() {
    showDialog(
      context: context,
      builder: (context) => FutureBuilder<Map<String, dynamic>>(
        future: _loadTokenUsageStats(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Dialog(
              child: Container(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          
          if (snapshot.hasError) {
            return Dialog(
              child: Container(
                padding: EdgeInsets.all(24),
                child: Text('Error loading token statistics: ${snapshot.error}'),
              ),
            );
          }
          
          final stats = snapshot.data ?? {};
          final totalTokens = stats['total_tokens_used'] ?? 0;
          final totalAnalyses = stats['total_analyses'] ?? 0;
          final dailyTokens = stats['daily_tokens'] ?? 0;
          final dailyAnalyses = stats['daily_analyses'] ?? 0;
          
          return Dialog(
            child: Container(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Token Usage Statistics',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  Text('Total tokens used: $totalTokens'),
                  Text('Total analyses: $totalAnalyses'),
                  Text('Today\'s tokens: $dailyTokens'),
                  Text('Today\'s analyses: $dailyAnalyses'),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Close'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Load token usage stats
  Future<Map<String, dynamic>> _loadTokenUsageStats() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {};
      
      final databaseRef = FirebaseDatabase.instance.ref();
      final totalsSnapshot = await databaseRef.child('users/users/${user.uid}/token_totals').get();
      Map<String, dynamic> stats = {};
      
      if (totalsSnapshot.exists) {
        final totals = Map<String, dynamic>.from(totalsSnapshot.value as Map<dynamic, dynamic>);
        stats['total_tokens_used'] = totals['total_tokens_used'] ?? 0;
        stats['total_analyses'] = totals['total_analyses'] ?? 0;
      }
      
      final today = DateTime.now().toIso8601String().split('T')[0];
      final dailySnapshot = await databaseRef.child('users/users/${user.uid}/daily_token_usage/$today').get();
      
      if (dailySnapshot.exists) {
        final daily = Map<String, dynamic>.from(dailySnapshot.value as Map<dynamic, dynamic>);
        stats['daily_tokens'] = daily['tokens_used'] ?? 0;
        stats['daily_analyses'] = daily['analyses_count'] ?? 0;
      } else {
        stats['daily_tokens'] = 0;
        stats['daily_analyses'] = 0;
      }
      
      return stats;
    } catch (e) {
      print('Error loading token usage stats: $e');
      return {};
    }
  }

  // Build AI loading message
  Widget _buildAILoadingMessage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
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
    );
  }

  // Build chat message
  Widget _buildChatMessage(ChatMessage message, int messageIndex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.isUser)
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
                Container(
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
              
              // Suggested questions
              if (!message.isUser && message.suggestedQuestions != null && message.suggestedQuestions!.isNotEmpty)
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
                        final idx = entry.key;
                        final question = entry.value;
                        return GestureDetector(
                          onTap: () {
                            _chatController.text = question;
                            _sendChatMessage();
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
                              style: const TextStyle(
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
          ),
        ),
      ],
    );
  }

  // Format analysis text
  Widget _formatAnalysisText(String analysis, bool isDark, ThemeData theme) {
    final sections = _identifySections(analysis);
    final baseStyle = TextStyle(
      fontSize: 16,
      color: isDark ? Colors.white : Colors.grey[800],
      height: 1.5,
    );
    final strongStyle = TextStyle(
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
                      TextStyle(
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

  // Identify sections in analysis text
  List<AnalysisSection> _identifySections(String analysis) {
    List<AnalysisSection> sections = [];
    final RegExp sectionRegex = RegExp(r'([\n\r]|^)([A-Z][A-Z0-9\s]+:)[\n\r]');
    final matches = sectionRegex.allMatches(analysis);
    
    if (matches.isEmpty) {
      sections.add(AnalysisSection('', analysis));
      return sections;
    }
    
    int lastEnd = 0;
    
    for (final match in matches) {
      final title = match.group(2) ?? '';
      final start = match.end;
      
      if (lastEnd < start) {
        final content = analysis.substring(lastEnd, start - title.length - 1).trim();
        if (content.isNotEmpty) {
          sections.add(AnalysisSection('', content));
        }
      }
      
      lastEnd = start;
    }
    
    if (lastEnd < analysis.length) {
      final content = analysis.substring(lastEnd).trim();
      if (content.isNotEmpty) {
        sections.add(AnalysisSection('', content));
      }
    }
    
    return sections;
  }

  // Build gradient text
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

  // Build markdown with gradient
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
} 