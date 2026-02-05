import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:intl/intl.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:twitter_api_v2/twitter_api_v2.dart' as v2;
import 'dart:math' as math;
import './history_page.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:image/image.dart' as img; // For Instagram image processing

// Lista di consigli virali da mostrare nel container inferiore
const List<String> viralTips = [
  "Videos with captions get 12% more views — most people scroll with sound off!",
  "Instagram Stories with polls or quizzes see 20% more engagement — interaction is king.",
  "Short-form video is the most shared content format across all major platforms.",
  "TikTok's algorithm resets daily. That means every video has a fresh shot at going viral!",
  "Hashtag challenges started on TikTok and now drive billions of views across platforms.",
  "The average person spends 2.5 hours a day on social media. That's a lot of chances to catch their eye!",
  "YouTube Shorts get pushed to over 2 billion users — great way to grow fast without long videos.",
  "Adding emojis in captions can increase engagement by up to 30%. 🎯🔥😎",
  "Reposting at the right time can double the performance of your original video.",
  "TikTok videos with text overlays keep people watching longer — great for storytelling!",
];

// Custom circular progress painter for upload visualization
class CircularProgressPainter extends CustomPainter {
  final List<ProgressSegment> segments;
  final double strokeWidth;
  final double gap;
  final bool smoothTransition;

  CircularProgressPainter({
    required this.segments,
    required this.strokeWidth,
    this.gap = 0.05,
    this.smoothTransition = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width / 2, size.height / 2) - strokeWidth / 2;
    
    // Calculate total active percentage (non-zero segments)
    double totalPercentage = segments.fold(0.0, (sum, item) => sum + item.percentage);
    double totalSegments = segments.where((s) => s.percentage > 0).length.toDouble();
    
    if (totalPercentage <= 0) return; 

    // Start angle (top of circle)
    double currentStartAngle = -math.pi / 2;
    
    // Small gap between segments (in radians)
    double gapSize = gap;
    
    // Track active segments to distribute gaps properly
    int activeSegmentCount = segments.where((s) => s.percentage > 0).length;
    
    // Calculate total non-gap angle available
    double totalAvailableAngle = 2 * math.pi - (activeSegmentCount > 1 ? (activeSegmentCount - 1) * gapSize : 0);
    
    // Create shadow paint for glow effect
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3);
    
    // Draw segments
    for (var segment in segments) {
      // Skip zero-percentage segments
      if (segment.percentage <= 0) continue;
      
      // Calculate the angle for this segment
      final segmentPercentage = segment.percentage / 100;
      final sweepAngle = segmentPercentage * totalAvailableAngle;
      
      // Create smooth gradient paint for segments
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      
      // If smooth transition enabled, apply radial gradient 
      if (smoothTransition) {
        // Use radial gradient to create a smoother appearance
        paint.shader = RadialGradient(
          colors: [
            segment.color.withOpacity(0.9),
            segment.color,
          ],
          stops: [0.0, 1.0],
          center: Alignment.center,
        ).createShader(Rect.fromCircle(
          center: center,
          radius: radius,
        ));
      } else {
        paint.color = segment.color;
      }
      
      // Optional: Draw subtle shadow for depth
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius + 1),
        currentStartAngle,
        sweepAngle,
        false,
        shadowPaint,
      );
      
      // Draw the segment
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        currentStartAngle,
        sweepAngle,
        false,
        paint,
      );
      
      // Update the starting angle for the next segment, adding the gap
      currentStartAngle += sweepAngle + gapSize;
    }
  }

  @override
  bool shouldRepaint(covariant CircularProgressPainter oldDelegate) {
    return oldDelegate.segments != segments ||
           oldDelegate.strokeWidth != strokeWidth ||
           oldDelegate.gap != gap ||
           oldDelegate.smoothTransition != smoothTransition;
  }
}

// Model for progress segment data
class ProgressSegment {
  final String name;
  final double percentage;
  final Color color;

  ProgressSegment({required this.name, required this.percentage, required this.color});
}

class InstagramUploadPage extends StatefulWidget {
  final File mediaFile;
  // Nuove liste per supportare più media (carosello)
  final List<File>? mediaFiles;
  final List<bool>? isImageFiles;
  final String title;
  final String description;
  final bool isImageFile;
  final Map<String, List<String>> selectedAccounts;
  final Map<String, List<Map<String, dynamic>>> socialAccounts;
  final Map<String, String> instagramContentType;
  final Map<String, Map<String, String>> platformDescriptions;
  final String? draftId; // Add draft ID parameter
  final File? youtubeThumbnailFile; // Per la miniatura personalizzata di YouTube
  final Map<String, Map<String, dynamic>>? tiktokOptions; // Opzioni TikTok per ogni account
  final Map<String, Map<String, dynamic>>? youtubeOptions; // Opzioni YouTube per ogni account

  const InstagramUploadPage({
    Key? key,
    required this.mediaFile,
    this.mediaFiles,
    this.isImageFiles,
    required this.title,
    required this.description,
    required this.selectedAccounts,
    required this.socialAccounts,
    this.isImageFile = false,
    this.instagramContentType = const {},
    this.platformDescriptions = const {},
    this.draftId, // Add draft ID parameter
    this.youtubeThumbnailFile, // Per la miniatura personalizzata di YouTube
    this.tiktokOptions, // Opzioni TikTok per ogni account
    this.youtubeOptions, // Opzioni YouTube per ogni account
  }) : super(key: key);

  @override
  State<InstagramUploadPage> createState() => _InstagramUploadPageState();
}

class _InstagramUploadPageState extends State<InstagramUploadPage> with TickerProviderStateMixin {
  bool _isUploading = false;
  String _statusMessage = 'Preparing upload...';
  double _uploadProgress = 0.0;
  String? _cloudflareUrl;
  // Nuova lista di URL Cloudflare per supportare più media
  List<String> _cloudflareUrls = [];
  String? _errorMessage;
  bool _uploadComplete = false;
  
  // Thumbnail variables
  String? _thumbnailPath;
  String? _thumbnailCloudflareUrl;

  // Liste locali di media e flag immagine per gestire il carosello
  List<File> _mediaFiles = [];
  List<bool> _isImageFiles = [];
  
  // Progress tracking per account
  Map<String, double> _accountProgress = {};
  Map<String, String> _accountStatus = {};
  Map<String, bool> _accountComplete = {};
  Map<String, String?> _accountError = {};
  
  // Selected Instagram accounts (from previous page)
  List<Map<String, dynamic>> _instagramAccounts = [];
  
  // Selected YouTube accounts (from previous page)
  List<Map<String, dynamic>> _youtubeAccounts = [];
  
  // Aggiungo variabili per la gestione dei crediti
  bool _isPremium = false;
  int _currentCredits = 0;
  int _creditsDeducted = 0;
  
  // Map to track YouTube upload attempts per account
  final Map<String, int> _youtubeUploadAttempts = {};
  final int _maxYouTubeAttempts = 3;
  
  // Selected Twitter accounts (from previous page)
  List<Map<String, dynamic>> _twitterAccounts = [];
  
  // Map to track Twitter upload attempts per account
  final Map<String, int> _twitterUploadAttempts = {};
  final int _maxTwitterAttempts = 3;
  
  // Selected Threads accounts (from previous page)
  List<Map<String, dynamic>> _threadsAccounts = [];
  
  // Map to track Threads upload attempts per account
  final Map<String, int> _threadsUploadAttempts = {};
  final int _maxThreadsAttempts = 3;
  
  // Selected Facebook accounts (from previous page)
  List<Map<String, dynamic>> _facebookAccounts = [];
  
  // Map to track Facebook upload attempts per account
  final Map<String, int> _facebookUploadAttempts = {};
  final int _maxFacebookAttempts = 3;
  
  // Selected TikTok accounts (from previous page)
  List<Map<String, dynamic>> _tiktokAccounts = [];
  
  // Map to track TikTok upload attempts per account
  final Map<String, int> _tiktokUploadAttempts = {};
  final int _maxTikTokAttempts = 3;
  
  // TikTok API credentials - LIVE APP (requires Content Sharing Audit for public posts)
  final String _tiktokClientKey = 'awfszvwmbv73a9u9';
  final String _tiktokClientSecret = 'A5JTgaY8v7BdNBegStGDJgQyw7wuEDWG';
  
  // Facebook API constants
  final String _facebookApiVersion = 'v23.0';
  final String _facebookAppId = '1256861902462549';
  final String _facebookAppSecret = '6a0796dfae1f56a8e528fe5b83ec6fa6';
  
  // Timer for auto-rotating tips
  Timer? _tipsTimer;
  // Current tip index
  int _currentTipIndex = 0;
  // To track if tips section is expanded or collapsed
  bool _isTipsExpanded = true;
  // Animation controllers for tips section
  late AnimationController _tipsAnimController;
  late Animation<double> _tipsHeightAnimation;
  late Animation<double> _tipsOpacityAnimation;
  
  // Platform colors for UI display
  final Map<String, Color> _platformColors = {
    'TikTok': const Color(0xFFC974E8),
    'YouTube': const Color(0xFFE57373),
    'Facebook': const Color(0xFF64B5F6),
    'Twitter': const Color(0xFF4FC3F7),
    'Threads': const Color(0xFFF7C167),
    'Instagram': const Color(0xFFE040FB),
    'file_structuring': const Color(0xFF6C63FF), // Changed from cloudflare to file_structuring
  };
  
  // Track completed platforms for circular progress
  Set<String> _completedPlatforms = {};
  
  // Track total selected accounts for calculating progress segments
  int _totalSelectedAccounts = 0;
  
  // Map to store profile images for accounts
  Map<String, String?> _profileImages = {};
  
  // Flag to track if upload history has been saved to Firebase
  bool _uploadHistorySaved = false;
  
  // Map to store post_id and media_id for each account after successful upload
  Map<String, String> _accountPostIds = {};
  Map<String, String> _accountMediaIds = {};
  
  @override
  void initState() {
    super.initState();
    
    // Inizializza le liste di media (singolo file o carosello)
    if (widget.mediaFiles != null && widget.mediaFiles!.isNotEmpty) {
      _mediaFiles = List<File>.from(widget.mediaFiles!);
      if (widget.isImageFiles != null && widget.isImageFiles!.isNotEmpty) {
        _isImageFiles = List<bool>.from(widget.isImageFiles!);
      } else {
        _isImageFiles = List<bool>.generate(
          _mediaFiles.length,
          (_) => widget.isImageFile,
        );
      }
    } else {
      _mediaFiles = [widget.mediaFile];
      _isImageFiles = [widget.isImageFile];
    }
    
    // Tips animation controller
    _tipsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    _tipsHeightAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _tipsAnimController,
      curve: Curves.easeInOut,
    ));
    
    _tipsOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _tipsAnimController,
      curve: Curves.easeIn,
    ));
    
    // Set initial state
    if (_isTipsExpanded) {
      _tipsAnimController.value = 1.0;
    }
    
    // Start the tips timer to auto-rotate tips every 10 seconds
    _startTipsTimer();
    
    // Automatically set up accounts from parameters
    _setupSelectedAccounts();
    
    // Calculate total number of selected accounts for progress segments
    _totalSelectedAccounts = _instagramAccounts.length + 
                            _youtubeAccounts.length + 
                            _twitterAccounts.length + 
                            _threadsAccounts.length + 
                            _facebookAccounts.length + 
                            _tiktokAccounts.length;
                            
    // Load profile images for accounts
    _loadProfileImages();
    
    // Controlla lo status premium dell'utente
    _checkUserPremiumStatus();
    
    // Start upload automatically after a short delay
    Future.delayed(Duration(milliseconds: 800), () {
      if (mounted && !_isUploading && !_uploadComplete && 
          (_instagramAccounts.isNotEmpty || _youtubeAccounts.isNotEmpty || 
           _twitterAccounts.isNotEmpty || _threadsAccounts.isNotEmpty ||
           _facebookAccounts.isNotEmpty || _tiktokAccounts.isNotEmpty)) {
        _startUpload();
      }
    });
  }
  
  @override
  void dispose() {
    // Cancel the timer when the widget is disposed
    _tipsTimer?.cancel();
    _tipsAnimController.dispose();
    
    // Before disposing, try to save upload history if there were successful uploads
    // but the user navigated away before completion
    if (!_uploadHistorySaved && _completedPlatforms.isNotEmpty) {
      _saveUploadHistory();
    }
    
    super.dispose();
  }
  
  void _startTipsTimer() {
    _tipsTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (mounted && _isTipsExpanded) {
        setState(() {
          _currentTipIndex = (_currentTipIndex + 1) % viralTips.length;
        });
      }
    });
  }

  // Move to next tip
  void _nextTip() {
    if (!_isTipsExpanded) return;
    
    setState(() {
      _currentTipIndex = (_currentTipIndex + 1) % viralTips.length;
    });
    
    // Reset the timer when manually changing tip
    _tipsTimer?.cancel();
    _startTipsTimer();
  }

  // Toggle tips section visibility
  void _toggleTipsVisibility() {
    setState(() {
      _isTipsExpanded = !_isTipsExpanded;
      if (_isTipsExpanded) {
        _tipsAnimController.forward();
      } else {
        _tipsAnimController.reverse();
      }
    });
  }
  
  // Setup selected accounts from parameters
  void _setupSelectedAccounts() {
    try {
      // Get Instagram accounts from the selectedAccounts map
      if (widget.selectedAccounts.containsKey('Instagram') && 
          widget.selectedAccounts['Instagram']!.isNotEmpty) {
        
        final instagramAccountIds = widget.selectedAccounts['Instagram']!;
        
        // Find the full account data from socialAccounts
        if (widget.socialAccounts.containsKey('Instagram')) {
          final accounts = widget.socialAccounts['Instagram']!;
          
          // Filter to only include selected accounts
          _instagramAccounts = accounts
              .where((account) => instagramAccountIds.contains(account['id']))
              .toList();
          
          // Initialize progress tracking for each account
          for (var account in _instagramAccounts) {
            final accountId = account['id'];
            _accountProgress[accountId] = 0.0;
            _accountStatus[accountId] = 'Pending...';
            _accountComplete[accountId] = false;
          }
          
          if (_instagramAccounts.isEmpty) {
            setState(() {
          _errorMessage = 'No Instagram account selected';
            });
          }
        }
      }
      
      // Get YouTube accounts from the selectedAccounts map
      if (widget.selectedAccounts.containsKey('YouTube') && 
          widget.selectedAccounts['YouTube']!.isNotEmpty) {
        
        final youtubeAccountIds = widget.selectedAccounts['YouTube']!;
        
        // Find the full account data from socialAccounts
        if (widget.socialAccounts.containsKey('YouTube')) {
          final accounts = widget.socialAccounts['YouTube']!;
          
          // Filter to only include selected accounts
          _youtubeAccounts = accounts
              .where((account) => youtubeAccountIds.contains(account['id']))
              .toList();
          
          // Initialize progress tracking for each account
          for (var account in _youtubeAccounts) {
            final accountId = account['id'];
            _accountProgress[accountId] = 0.0;
            _accountStatus[accountId] = 'Pending...';
            _accountComplete[accountId] = false;
          }
        }
      }
      
      // Get Twitter accounts from the selectedAccounts map
      if (widget.selectedAccounts.containsKey('Twitter') && 
          widget.selectedAccounts['Twitter']!.isNotEmpty) {
        
        final twitterAccountIds = widget.selectedAccounts['Twitter']!;
        
        // Find the full account data from socialAccounts
        if (widget.socialAccounts.containsKey('Twitter')) {
          final accounts = widget.socialAccounts['Twitter']!;
          
          // Filter to only include selected accounts
          _twitterAccounts = accounts
              .where((account) => twitterAccountIds.contains(account['id']))
              .toList();
          
          // Initialize progress tracking for each account
          for (var account in _twitterAccounts) {
            final accountId = account['id'];
            _accountProgress[accountId] = 0.0;
            _accountStatus[accountId] = 'Pending...';
            _accountComplete[accountId] = false;
          }
        }
      }
      
      // Get Threads accounts from the selectedAccounts map
      if (widget.selectedAccounts.containsKey('Threads') && 
          widget.selectedAccounts['Threads']!.isNotEmpty) {
        
        final threadsAccountIds = widget.selectedAccounts['Threads']!;
        
        // Find the full account data from socialAccounts
        if (widget.socialAccounts.containsKey('Threads')) {
          final accounts = widget.socialAccounts['Threads']!;
          
          // Filter to only include selected accounts
          _threadsAccounts = accounts
              .where((account) => threadsAccountIds.contains(account['id']))
              .toList();
          
          // Initialize progress tracking for each account
          for (var account in _threadsAccounts) {
            final accountId = account['id'];
            _accountProgress[accountId] = 0.0;
            _accountStatus[accountId] = 'Pending...';
            _accountComplete[accountId] = false;
          }
        }
      }
      
      // Get Facebook accounts from the selectedAccounts map
      if (widget.selectedAccounts.containsKey('Facebook') && 
          widget.selectedAccounts['Facebook']!.isNotEmpty) {
        
        final facebookAccountIds = widget.selectedAccounts['Facebook']!;
        
        // Find the full account data from socialAccounts
        if (widget.socialAccounts.containsKey('Facebook')) {
          final accounts = widget.socialAccounts['Facebook']!;
          
          // Filter to only include selected accounts
          _facebookAccounts = accounts
              .where((account) => facebookAccountIds.contains(account['id']))
              .toList();
          
          // Initialize progress tracking for each account
          for (var account in _facebookAccounts) {
            final accountId = account['id'];
            _accountProgress[accountId] = 0.0;
            _accountStatus[accountId] = 'Pending...';
            _accountComplete[accountId] = false;
          }
        }
      }
      
      // Get TikTok accounts from the selectedAccounts map
      if (widget.selectedAccounts.containsKey('TikTok') && 
          widget.selectedAccounts['TikTok']!.isNotEmpty) {
        
        final tiktokAccountIds = widget.selectedAccounts['TikTok']!;
        
        // Find the full account data from socialAccounts
        if (widget.socialAccounts.containsKey('TikTok')) {
          final accounts = widget.socialAccounts['TikTok']!;
          
          // Filter to only include selected accounts
          _tiktokAccounts = accounts
              .where((account) => tiktokAccountIds.contains(account['id']))
              .toList();
          
          // Initialize progress tracking for each account
          for (var account in _tiktokAccounts) {
            final accountId = account['id'];
            _accountProgress[accountId] = 0.0;
            _accountStatus[accountId] = 'Pending...';
            _accountComplete[accountId] = false;
          }
        }
      }
      
      // Show error if no accounts selected
      if (_instagramAccounts.isEmpty && _youtubeAccounts.isEmpty && 
          _twitterAccounts.isEmpty && _threadsAccounts.isEmpty &&
          _facebookAccounts.isEmpty && _tiktokAccounts.isEmpty) {
        setState(() {
      _errorMessage = 'No social account selected';
        });
      }
    } catch (e) {
      setState(() {
    _errorMessage = 'Error fetching accounts: $e';
      });
    }
  }
  
  // Start the upload process for all selected accounts
  Future<void> _startUpload() async {
    // Validate selection
    if (_instagramAccounts.isEmpty && _youtubeAccounts.isEmpty && 
        _twitterAccounts.isEmpty && _threadsAccounts.isEmpty &&
        _facebookAccounts.isEmpty && _tiktokAccounts.isEmpty) {
      setState(() {
      _errorMessage = 'No social account selected';
      });
      return;
    }
    
    setState(() {
      _isUploading = true;
      _errorMessage = null;
      _uploadProgress = 0.0;
    _statusMessage = 'Initializing upload...';
    });
    
    try {
      // Step 1: Upload the file to Cloudflare/Firebase Storage
      await _uploadToCloudflare();
      
      // Step 1.5: Generate and upload thumbnail if it's a video
      if (!widget.isImageFile) {
        setState(() {
      _statusMessage = 'Generating thumbnail...';
        });
        
        try {
          // Generate thumbnail
          await _generateThumbnail();
          
          if (_thumbnailPath != null) {
            setState(() {
              _statusMessage = 'Uploading thumbnail to Cloudflare...';
            });
            
            // Upload thumbnail to Cloudflare
            await _uploadThumbnailToCloudflare();
            
            setState(() {
              _statusMessage = 'Thumbnail uploaded successfully';
            });
          }
        } catch (e) {
          print('Error generating/uploading thumbnail: $e');
          // Continue without thumbnail
        }
      }
      
      // Step 2: Upload to Instagram for each account (if any)
      List<Future<void>> instagramUploadFutures = [];
      
      for (var account in _instagramAccounts) {
        final accountId = account['id'] as String;
        
        // Get content type for this account
        final contentType = widget.instagramContentType[accountId] ?? 'Post';
        
        // Get platform-specific description if available
        String postDescription = widget.description;
        if (widget.platformDescriptions.containsKey('Instagram') && 
            widget.platformDescriptions['Instagram']!.containsKey(accountId)) {
          postDescription = widget.platformDescriptions['Instagram']![accountId]!;
        }
        
        // Start upload for this account in parallel
        instagramUploadFutures.add(
          _uploadToInstagram(
            account: account, 
            contentType: contentType,
            description: postDescription
          )
        );
      }
      
      // Step 3: Upload to YouTube for each account (SEQUENTIAL to avoid Google Sign-In conflicts)
      // YouTube accounts MUST be uploaded sequentially due to Google Sign-In limitations
      for (var account in _youtubeAccounts) {
        final accountId = account['id'] as String;
        
        // Get platform-specific description if available
        String videoDescription = widget.description;
        if (widget.platformDescriptions.containsKey('YouTube') && 
            widget.platformDescriptions['YouTube']!.containsKey(accountId)) {
          videoDescription = widget.platformDescriptions['YouTube']![accountId]!;
        }
        
        // Get platform-specific title if available
        String videoTitle;
        if (widget.platformDescriptions.containsKey('YouTube') &&
            widget.platformDescriptions['YouTube']!.containsKey('${accountId}_title')) {
          videoTitle = widget.platformDescriptions['YouTube']!['${accountId}_title']!;
        } else {
          videoTitle = widget.title.isNotEmpty ? widget.title : widget.mediaFile.path.split('/').last;
        }
        
        // Upload sequentially (NOT in parallel) to avoid Google Sign-In conflicts
        await _uploadToYouTube(
          account: account,
          description: videoDescription,
          title: videoTitle
        );
      }
      
      // Step 4: Upload to Twitter for each account
      List<Future<void>> twitterUploadFutures = [];
      
      for (var account in _twitterAccounts) {
        final accountId = account['id'] as String;
        
        // Get platform-specific description if available
        String tweetText = widget.description;
        if (widget.platformDescriptions.containsKey('Twitter') && 
            widget.platformDescriptions['Twitter']!.containsKey(accountId)) {
          tweetText = widget.platformDescriptions['Twitter']![accountId]!;
        }
        
        // Start upload for this account in parallel
        twitterUploadFutures.add(
          _uploadToTwitter(
            account: account,
            description: tweetText
          )
        );
      }
      
      // Step 5: Upload to Threads for each account
      List<Future<void>> threadsUploadFutures = [];
      
      for (var account in _threadsAccounts) {
        final accountId = account['id'] as String;
        
        // Get platform-specific description if available
        String threadsText = widget.description;
        if (widget.platformDescriptions.containsKey('Threads') && 
            widget.platformDescriptions['Threads']!.containsKey(accountId)) {
          threadsText = widget.platformDescriptions['Threads']![accountId]!;
        }
        
        // Start upload for this account in parallel
        threadsUploadFutures.add(
          _uploadToThreads(
            account: account,
            description: threadsText
          )
        );
      }
      
      // Step 6: Upload to Facebook for each account
      List<Future<void>> facebookUploadFutures = [];
      
      for (var account in _facebookAccounts) {
        final accountId = account['id'] as String;
        
        // Get platform-specific description if available
        String facebookText = widget.description;
        if (widget.platformDescriptions.containsKey('Facebook') && 
            widget.platformDescriptions['Facebook']!.containsKey(accountId)) {
          facebookText = widget.platformDescriptions['Facebook']![accountId]!;
        }
        
        // Start upload for this account in parallel
        facebookUploadFutures.add(
          _uploadToFacebook(
            account: account,
            description: facebookText
          )
        );
      }
      
      // Step 7: Upload to TikTok for each account
      List<Future<void>> tiktokUploadFutures = [];
      
      for (var account in _tiktokAccounts) {
        final accountId = account['id'] as String;
        
        // Get platform-specific description if available
        String tiktokText = widget.description;
        if (widget.platformDescriptions.containsKey('TikTok') && 
            widget.platformDescriptions['TikTok']!.containsKey(accountId)) {
          tiktokText = widget.platformDescriptions['TikTok']![accountId]!;
        }
        
        // Start upload for this account in parallel
        tiktokUploadFutures.add(
          _uploadToTikTok(
            account: account,
            description: tiktokText
          )
        );
      }
      
      // Wait for all uploads to complete (YouTube uploads are already complete since they're sequential)
      List<Future<void>> allUploadFutures = [
        ...instagramUploadFutures, 
        // youtubeUploadFutures removed - YouTube uploads are sequential
        ...twitterUploadFutures,
        ...threadsUploadFutures,
        ...facebookUploadFutures,
        ...tiktokUploadFutures
      ];
      await Future.wait(allUploadFutures);
      
      // Check if all accounts completed successfully
      bool allInstagramComplete = _instagramAccounts.isEmpty || _instagramAccounts.every(
        (account) => _accountComplete[account['id']] == true
      );
      
      bool allYoutubeComplete = _youtubeAccounts.isEmpty || _youtubeAccounts.every(
        (account) => _accountComplete[account['id']] == true
      );
      
      bool allTwitterComplete = _twitterAccounts.isEmpty || _twitterAccounts.every(
        (account) => _accountComplete[account['id']] == true
      );
      
      bool allThreadsComplete = _threadsAccounts.isEmpty || _threadsAccounts.every(
        (account) => _accountComplete[account['id']] == true
      );
      
      bool allFacebookComplete = _facebookAccounts.isEmpty || _facebookAccounts.every(
        (account) => _accountComplete[account['id']] == true
      );
      
      bool allTikTokComplete = _tiktokAccounts.isEmpty || _tiktokAccounts.every(
        (account) => _accountComplete[account['id']] == true
      );
      
      setState(() {
        _uploadComplete = allInstagramComplete && allYoutubeComplete && 
                          allTwitterComplete && allThreadsComplete &&
                          allFacebookComplete && allTikTokComplete;
        _isUploading = false;
        _statusMessage = _uploadComplete 
            ? 'Upload completed successfully!' 
            : 'Upload completed with some errors';
        _uploadProgress = 1.0;
      });
      
      // Save upload history to Firebase if there are any completed uploads
      if (_uploadComplete || 
          allInstagramComplete || allYoutubeComplete || allTwitterComplete || 
          allThreadsComplete || allFacebookComplete || allTikTokComplete) {
        await _saveUploadHistory();
        
        // Deduct credits for non-premium users
        if (!_isPremium) {
          print('User is not premium, deducting credits...');
          await _deductCredits();
        } else {
          print('User is premium, skipping credit deduction');
        }
      }
      
      // Mostra il popup di successo per utenti non premium
      if (_uploadComplete && mounted) {
        // Aggiorna i crediti attuali prima di mostrare il popup
        await _checkUserPremiumStatus();
        if (!_isPremium) {
        _showNonPremiumSuccessDialog();
        } else {
          _showPremiumSuccessDialog();
        }
      }
      
    } catch (e) {
      setState(() {
        _isUploading = false;
        _errorMessage = 'Error during upload: $e';
      });
    }
  }
  
  // Upload file to Cloudflare R2
  Future<void> _uploadToCloudflare() async {
    // Start with a small initial progress for immediate visual feedback
    setState(() {
      _statusMessage = 'Initializing upload...';
      _uploadProgress = 0.01;
      // Add cloudflare to progress tracking but will update percentage as upload progresses
      
      // Update all accounts' status
      for (var account in _instagramAccounts) {
        _accountStatus[account['id']] = 'Initializing upload...';
        _accountProgress[account['id']] = 0.01;
      }
    });
    
    // Show preparing progress animation over a short period
    for (int i = 1; i <= 5; i++) {
      if (!mounted) break;
      await Future.delayed(Duration(milliseconds: 150));
      
      setState(() {
        _statusMessage = 'Preparing upload...';
        _uploadProgress = 0.01 + (i * 0.008);
        
        // Update all accounts' status
        for (var account in _instagramAccounts) {
          _accountStatus[account['id']] = 'Preparing upload...';
          _accountProgress[account['id']] = 0.01 + (i * 0.008);
        }
      });
    }
    
    setState(() {
      _statusMessage = 'File structuring for uploads...';
      _uploadProgress = 0.05;
      
      // Update all accounts' status
      for (var account in _instagramAccounts) {
        _accountStatus[account['id']] = 'File structuring for uploads...';
        _accountProgress[account['id']] = 0.05;
      }
      
      // Update YouTube accounts' status
      for (var account in _youtubeAccounts) {
        _accountStatus[account['id']] = 'Upload file architecture...';
        _accountProgress[account['id']] = 0.1;
      }
      
      // Update Twitter accounts' status
      for (var account in _twitterAccounts) {
        _accountStatus[account['id']] = 'Upload file architecture...';
        _accountProgress[account['id']] = 0.1;
      }
      
      // Update Threads accounts' status
      for (var account in _threadsAccounts) {
        _accountStatus[account['id']] = 'Upload file architecture...';
        _accountProgress[account['id']] = 0.1;
      }
      
      // Update Facebook accounts' status
      for (var account in _facebookAccounts) {
        _accountStatus[account['id']] = 'Upload file architecture...';
        _accountProgress[account['id']] = 0.1;
      }
      
      // Update TikTok accounts' status
      for (var account in _tiktokAccounts) {
        _accountStatus[account['id']] = 'Upload file architecture...';
        _accountProgress[account['id']] = 0.1;
      }
    });
    
    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Utente non autenticato');
      }
      
      // Determina il file principale (primo media del carosello o singolo file)
      final File primaryFile = _mediaFiles.isNotEmpty ? _mediaFiles.first : widget.mediaFile;
      final bool primaryIsImage = _isImageFiles.isNotEmpty ? _isImageFiles.first : widget.isImageFile;
      
      // Cloudflare R2 credentials - usando credenziali corrette da storage.md
      final String accessKeyId = '5e181628bad7dc5481c92c6f3899efd6';
      final String secretKey = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
      final String endpoint = 'https://3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com';
      final String bucketName = 'videos';
      final String accountId = '3d945eb681944ec5965fecf275e41a9b';
      final String region = 'auto'; // R2 usa 'auto' come regione
      
      // Generate a unique filename per il file principale
      final String fileExtension = path.extension(primaryFile.path);
      final String fileName = 'media_${DateTime.now().millisecondsSinceEpoch}_${currentUser.uid}$fileExtension';
      final String fileKey = fileName;
      
      // Get file bytes and size
      final bytes = await primaryFile.readAsBytes();
      final contentLength = bytes.length;
      
      // Calcola l'hash SHA-256 del contenuto
      final List<int> contentHash = sha256.convert(bytes).bytes;
      final String payloadHash = hex.encode(contentHash);
      
      // Set up request information
      final String httpMethod = 'PUT';
      final String contentType = primaryIsImage ? 'image/jpeg' : 'video/mp4';
      
      // SigV4 richiede data in formato ISO8601
      final now = DateTime.now().toUtc();
      final String amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
      final String dateStamp = DateFormat("yyyyMMdd").format(now);
      
      // Host e URI
      final Uri uri = Uri.parse('$endpoint/$bucketName/$fileKey');
      final String host = uri.host;
      
      // Canonical request
      final Map<String, String> headers = {
        'host': host,
        'content-type': contentType,
        'x-amz-content-sha256': payloadHash,
        'x-amz-date': amzDate
      };
      
      String canonicalHeaders = '';
      String signedHeaders = '';
      
      // Ordina gli header in ordine lessicografico
      final sortedHeaderKeys = headers.keys.toList()..sort();
      for (final key in sortedHeaderKeys) {
        canonicalHeaders += '${key.toLowerCase()}:${headers[key]}\n';
        signedHeaders += '${key.toLowerCase()};';
      }
      signedHeaders = signedHeaders.substring(0, signedHeaders.length - 1); // Rimuovi l'ultimo punto e virgola
      
      // Canonical request
      final String canonicalUri = '/$bucketName/$fileKey';
      final String canonicalQueryString = '';
      final String canonicalRequest = '$httpMethod\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
      
      // String to sign
      final String algorithm = 'AWS4-HMAC-SHA256';
      final String scope = '$dateStamp/$region/s3/aws4_request';
      final String stringToSign = '$algorithm\n$amzDate\n$scope\n${hex.encode(sha256.convert(utf8.encode(canonicalRequest)).bytes)}';
      
      // Firma
      List<int> getSignatureKey(String key, String dateStamp, String regionName, String serviceName) {
        final kDate = Hmac(sha256, utf8.encode('AWS4$key')).convert(utf8.encode(dateStamp)).bytes;
        final kRegion = Hmac(sha256, kDate).convert(utf8.encode(regionName)).bytes;
        final kService = Hmac(sha256, kRegion).convert(utf8.encode(serviceName)).bytes;
        final kSigning = Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
        return kSigning;
      }
      
      final signingKey = getSignatureKey(secretKey, dateStamp, region, 's3');
      final signature = hex.encode(Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).bytes);
      
      // Authorization header
      final String authorizationHeader = '$algorithm Credential=$accessKeyId/$scope, SignedHeaders=$signedHeaders, Signature=$signature';
      
      // Create request URL
      final String uploadUrl = '$endpoint/$bucketName/$fileKey';
      
      // Create request with headers
      final http.Request request = http.Request('PUT', Uri.parse(uploadUrl));
      request.headers['Host'] = host;
      request.headers['Content-Type'] = contentType;
      request.headers['Content-Length'] = contentLength.toString();
      request.headers['X-Amz-Content-Sha256'] = payloadHash;
      request.headers['X-Amz-Date'] = amzDate;
      request.headers['Authorization'] = authorizationHeader;
      
      // Add file body
      request.bodyBytes = bytes;
      
      // Setup progress tracking
      int bytesUploaded = 0;
      final streamedRequest = http.StreamedRequest(
        request.method,
        request.url,
      );
      
      // Add all headers to streamed request
      request.headers.forEach((key, value) {
        streamedRequest.headers[key] = value;
      });
      
      // Set up progress tracking as data is sent
      final progressStream = Stream<List<int>>.fromIterable(
        [bytes],
      ).transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            bytesUploaded += data.length;
            final progress = bytesUploaded / contentLength;
            
            // Show more gradual progression: from 0.05 to 0.45 (leaves space for initialization and completion)
            final visualProgress = 0.05 + (progress * 0.40);
            
            setState(() {
              _uploadProgress = visualProgress;
              _statusMessage = 'File structuring: ${(_uploadProgress * 100).toInt()}%';
              
              // Update all accounts' progress
              for (var account in _instagramAccounts) {
                _accountProgress[account['id']] = visualProgress;
                _accountStatus[account['id']] = 'File structuring: ${(_accountProgress[account['id']]! * 100).toInt()}%';
              }
              
              // Update all YouTube accounts' progress
              for (var account in _youtubeAccounts) {
                _accountProgress[account['id']] = 0.1 + (progress * 0.4);
                _accountStatus[account['id']] = 'Upload file architecture: ${(_accountProgress[account['id']]! * 100).toInt()}%';
              }
              
              // Update all Twitter accounts' progress
              for (var account in _twitterAccounts) {
                _accountProgress[account['id']] = 0.1 + (progress * 0.4);
                _accountStatus[account['id']] = 'Upload file architecture: ${(_accountProgress[account['id']]! * 100).toInt()}%';
              }
              
              // Update all Threads accounts' progress
              for (var account in _threadsAccounts) {
                _accountProgress[account['id']] = 0.1 + (progress * 0.4);
                _accountStatus[account['id']] = 'Upload file architecture: ${(_accountProgress[account['id']]! * 100).toInt()}%';
              }
              
              // Update all Facebook accounts' progress
              for (var account in _facebookAccounts) {
                _accountProgress[account['id']] = 0.1 + (progress * 0.4);
                _accountStatus[account['id']] = 'Upload file architecture: ${(_accountProgress[account['id']]! * 100).toInt()}%';
              }
              
              // Update all TikTok accounts' progress
              for (var account in _tiktokAccounts) {
                _accountProgress[account['id']] = 0.1 + (progress * 0.4);
                _accountStatus[account['id']] = 'Upload file architecture: ${(_accountProgress[account['id']]! * 100).toInt()}%';
              }
            });
            sink.add(data);
          },
        ),
      );
      
      // Add the progress stream to the request
      await for (final chunk in progressStream) {
        streamedRequest.sink.add(chunk);
      }
      streamedRequest.sink.close();
      
      // Send the request and get the response
      final streamedResponse = await streamedRequest.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Generate public URL nel formato corretto
        // Usa il formato pub-[accountId].r2.dev
        final String publicUrl = 'https://pub-$accountId.r2.dev/$fileKey';
        
        print('File caricato con successo su Cloudflare R2');
        print('URL pubblico generato: $publicUrl');
        
        // Show completion animation
        for (int i = 1; i <= 10; i++) {
          if (!mounted) break;
          
          setState(() {
            double progressStep = 0.45 + (i * 0.005); // Progress from 45% to 50%
            _uploadProgress = progressStep;
            _statusMessage = 'File structuring: ${(progressStep * 100).toInt()}%';
            
            // Update all Instagram accounts' progress
            for (var account in _instagramAccounts) {
              _accountProgress[account['id']] = progressStep;
              _accountStatus[account['id']] = 'File structuring: ${(progressStep * 100).toInt()}%';
            }
          });
          
          await Future.delayed(Duration(milliseconds: 50));
        }
        
        setState(() {
          // Salva l'URL principale e inizializza la lista con il primo media
          _cloudflareUrl = publicUrl; // Use the correct public URL format
          _cloudflareUrls = [publicUrl];
          _uploadProgress = 0.5; // 50%
                    _statusMessage = 'File structured successfully';
          _completedPlatforms.add('file_structuring');
          
          // Update all Instagram accounts' progress
          for (var account in _instagramAccounts) {
            _accountProgress[account['id']] = 0.5;
            _accountStatus[account['id']] = 'File structured successfully';
            }
            
            // Update all YouTube accounts' progress
            for (var account in _youtubeAccounts) {
              _accountProgress[account['id']] = 0.5;
              _accountStatus[account['id']] = 'Upload file architecture';
            }
            
            // Update all Twitter accounts' progress
            for (var account in _twitterAccounts) {
              _accountProgress[account['id']] = 0.5;
              _accountStatus[account['id']] = 'Upload file architecture';
            }
            
            // Update all Threads accounts' progress
            for (var account in _threadsAccounts) {
              _accountProgress[account['id']] = 0.5;
              _accountStatus[account['id']] = 'Upload file architecture';
            }
            
            // Update all Facebook accounts' progress
            for (var account in _facebookAccounts) {
              _accountProgress[account['id']] = 0.5;
              _accountStatus[account['id']] = 'Upload file architecture';
            }
            
            // Update all TikTok accounts' progress
            for (var account in _tiktokAccounts) {
              _accountProgress[account['id']] = 0.5;
              _accountStatus[account['id']] = 'Upload file architecture';
            }
        });
        
        // Se ci sono più media nel carosello, carica anche gli altri su Cloudflare (senza modificare la UI principale)
        if (_mediaFiles.length > 1) {
          for (int i = 1; i < _mediaFiles.length; i++) {
            try {
              final File file = _mediaFiles[i];
              final bool isImage = i < _isImageFiles.length ? _isImageFiles[i] : primaryIsImage;
              final extraUrl = await _uploadSingleFileToCloudflareSilent(
                file,
                isImage: isImage,
              );
              if (extraUrl != null) {
                setState(() {
                  _cloudflareUrls.add(extraUrl);
                });
              }
            } catch (e) {
              print('Errore nel caricamento su Cloudflare R2 per media indice $i: $e');
              // In caso di errore su un media extra, continuiamo comunque con gli altri
            }
          }
        }
      } else {
        throw Exception('Errore nel caricamento su Cloudflare R2: Codice ${response.statusCode}, Risposta: ${response.body}');
      }
    } catch (e) {
      throw Exception('Errore nel caricamento su Cloudflare R2: $e');
    }
  }

  // Upload aggiuntivo di un singolo file su Cloudflare R2 senza aggiornare la UI principale
  Future<String?> _uploadSingleFileToCloudflareSilent(
    File file, {
    required bool isImage,
  }) async {
    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Utente non autenticato');
      }

      // Cloudflare R2 credentials
      final String accessKeyId = '5e181628bad7dc5481c92c6f3899efd6';
      final String secretKey = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
      final String endpoint = 'https://3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com';
      final String bucketName = 'videos';
      final String accountId = '3d945eb681944ec5965fecf275e41a9b';
      final String region = 'auto';

      // Unique filename for this media
      final String fileExtension = path.extension(file.path);
      final String fileName = 'media_${DateTime.now().millisecondsSinceEpoch}_${currentUser.uid}$fileExtension';
      final String fileKey = fileName;

      // Get file bytes and size
      final bytes = await file.readAsBytes();
      final contentLength = bytes.length;

      // SHA-256 hash
      final List<int> contentHash = sha256.convert(bytes).bytes;
      final String payloadHash = hex.encode(contentHash);

      // Request info
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
        'x-amz-date': amzDate,
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
      final String canonicalRequest =
          '$httpMethod\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';

      final String algorithm = 'AWS4-HMAC-SHA256';
      final String scope = '$dateStamp/$region/s3/aws4_request';
      final String stringToSign =
          '$algorithm\n$amzDate\n$scope\n${hex.encode(sha256.convert(utf8.encode(canonicalRequest)).bytes)}';

      List<int> getSignatureKey(String key, String dateStamp, String regionName, String serviceName) {
        final kDate = Hmac(sha256, utf8.encode('AWS4$key')).convert(utf8.encode(dateStamp)).bytes;
        final kRegion = Hmac(sha256, kDate).convert(utf8.encode(regionName)).bytes;
        final kService = Hmac(sha256, kRegion).convert(utf8.encode(serviceName)).bytes;
        final kSigning = Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
        return kSigning;
      }

      final signingKey = getSignatureKey(secretKey, dateStamp, region, 's3');
      final signature = hex.encode(Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).bytes);

      final String authorizationHeader =
          '$algorithm Credential=$accessKeyId/$scope, SignedHeaders=$signedHeaders, Signature=$signature';

      final String uploadUrl = '$endpoint/$bucketName/$fileKey';

      final http.Request request = http.Request('PUT', Uri.parse(uploadUrl));
      request.headers['Host'] = host;
      request.headers['Content-Type'] = contentType;
      request.headers['Content-Length'] = contentLength.toString();
      request.headers['X-Amz-Content-Sha256'] = payloadHash;
      request.headers['X-Amz-Date'] = amzDate;
      request.headers['Authorization'] = authorizationHeader;
      request.bodyBytes = bytes;

      final response = await http.Client().send(request);
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final String publicUrl = 'https://pub-$accountId.r2.dev/$fileKey';
        print('File aggiuntivo caricato su Cloudflare R2: $publicUrl');
        return publicUrl;
      } else {
        print('Errore nel caricamento aggiuntivo su Cloudflare R2: Code ${response.statusCode}, Body: $responseBody');
        return null;
      }
    } catch (e) {
      print('Errore nell\'upload aggiuntivo su Cloudflare R2: $e');
      return null;
    }
  }
  
  // Upload to Instagram using the Cloudflare URL for a specific account
  Future<void> _uploadToInstagram({
    required Map<String, dynamic> account,
    required String contentType,
    required String description
  }) async {
    final String accountId = account['id'];
    final bool isImage = _isImageFiles.isNotEmpty ? _isImageFiles.first : widget.isImageFile;
    final bool hasMultipleMedia = _cloudflareUrls.length > 1;
    
    if (_cloudflareUrl == null && _cloudflareUrls.isEmpty) {
      setState(() {
        _accountError[accountId] =
            'File URL is not available. Please restart this upload and try again.';
        _accountComplete[accountId] = true; // Mark as complete with error
      });
      return;
    }
    
    // Create a more gradual progress animation from 50% to 60%
    for (int i = 1; i <= 5; i++) {
      if (!mounted) break;
      
      setState(() {
        double progressStep = 0.5 + (i * 0.02); // Progress from 50% to 60% in steps
        _accountProgress[accountId] = progressStep;
        _accountStatus[accountId] = 'Preparing upload to Instagram...';
      });
      
      await Future.delayed(Duration(milliseconds: 100));
    }
    
    setState(() {
      _accountStatus[accountId] = 'Preparing upload to Instagram...';
      _accountProgress[accountId] = 0.6; // 60%
    });
    
    try {
      // Get Instagram account data
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Utente non autenticato');
      }
      
      // Get account data from Firebase
      final accountSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(currentUser.uid)
          .child('instagram')
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        throw Exception('Account Instagram non trovato');
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token'];
      final userId = accountData['user_id'] ?? accountId;
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Token di accesso Instagram non trovato');
      }
      
      // Se ci sono più media, usa il flusso dedicato per il carosello Instagram
      if (hasMultipleMedia) {
        await _uploadInstagramCarousel(
          accountId: accountId,
          userId: userId.toString(),
          accessToken: accessToken.toString(),
          description: description,
          contentType: contentType,
        );
        return;
      }
      
      // Verifica l'accessibilità dell'URL prima di procedere
      setState(() {
        _accountStatus[accountId] = 'Checking media accessibility...';
        _accountProgress[accountId] = 0.65;
      });
      
      // Assicurati che l'URL sia nel formato corretto (pub-[accountId].r2.dev)
      String cloudflareUrl = _cloudflareUrls.isNotEmpty ? _cloudflareUrls.first : _cloudflareUrl!;
      
      // Se non è nel formato corretto, lo convertiamo
      if (!cloudflareUrl.contains('pub-') || !cloudflareUrl.contains('.r2.dev')) {
        print('URL non nel formato pub-[accountId].r2.dev: $cloudflareUrl');
        
        // Estrai il nome del file dall'URL corrente
        final String fileName;
        if (cloudflareUrl.contains('/')) {
          fileName = cloudflareUrl.split('/').last;
        } else {
          fileName = cloudflareUrl;
        }
        
        // Costruisci l'URL nel formato corretto
        final String cloudflareAccountId = '3d945eb681944ec5965fecf275e41a9b';
        cloudflareUrl = 'https://pub-$cloudflareAccountId.r2.dev/$fileName';
        print('URL convertito nel formato corretto: $cloudflareUrl');
      }
      
      // For images, resize to Instagram-compatible aspect ratio
      String instagramImageUrl = cloudflareUrl;
      if (isImage) {
        setState(() {
          _accountStatus[accountId] = 'Resizing image for Instagram...';
          _accountProgress[accountId] = 0.68;
        });
        
        try {
          // Resize the image for Instagram
          final File primaryFile = _mediaFiles.isNotEmpty ? _mediaFiles.first : widget.mediaFile;
          final resizedImageFile = await _resizeImageForInstagram(primaryFile);
          
          if (resizedImageFile != null) {
            // Upload the resized image to Cloudflare
            setState(() {
              _accountStatus[accountId] = 'Uploading resized image...';
              _accountProgress[accountId] = 0.69;
            });
            
            // Upload resized image to Cloudflare
            final resizedCloudflareUrl = await _uploadResizedImageToCloudflare(resizedImageFile);
            
            if (resizedCloudflareUrl != null) {
              instagramImageUrl = resizedCloudflareUrl;
              print('Using resized image for Instagram: $instagramImageUrl');
            } else {
              print('Failed to upload resized image, using original');
            }
          } else {
            print('Failed to resize image, using original');
          }
        } catch (e) {
          print('Error processing image for Instagram: $e');
          // Continue with original image
        }
      }
      
      // Verifica l'accessibilità dell'URL
      bool isAccessible = await _verifyFileAccessibility(instagramImageUrl);
      
      if (!isAccessible) {
        print('ATTENZIONE: URL del file non accessibile pubblicamente: $instagramImageUrl');
        throw Exception('URL del file non accessibile pubblicamente. Instagram richiede URL accessibili.');
      } else {
        print('URL accessibile: $instagramImageUrl');
      }
      
      // Determine API version
      const apiVersion = 'v18.0';
      
      setState(() {
    _accountStatus[accountId] = 'Creating Instagram container...';
        _accountProgress[accountId] = 0.7; // 70%
      });
      
      // Create Instagram container based on media type
      String mediaType;
      
      if (!isImage) {
        // Per i video, usare sempre REELS come richiesto dall'API Instagram
        mediaType = 'REELS';
        print('Usando media_type=REELS per il video come richiesto da Instagram API');
      } else {
        // Per le immagini, seguire la logica precedente
        switch (contentType) {
          case 'Storia':
            mediaType = 'STORIES';
            break;
          case 'Reels':
            // Reels non supporta immagini, fallback a IMAGE
            mediaType = 'IMAGE';
            break;
          case 'Post':
          default:
            mediaType = 'IMAGE';
            break;
        }
      }
      
      final Map<String, String> requestBody = {
        'access_token': accessToken,
        'caption': description,
      };
      
      // Add appropriate URL based on media type
      if (isImage) {
        requestBody['image_url'] = instagramImageUrl;
      } else {
        requestBody['video_url'] = _cloudflareUrl!;
        requestBody['media_type'] = mediaType; // Ora sempre REELS per i video
        
        // Aggiungi parametri addizionali richiesti per i Reels
        if (_thumbnailCloudflareUrl != null) {
          // Se abbiamo una thumbnail specifica, usala
          requestBody['thumb_offset'] = '0'; // Usa il primo frame come thumbnail
          print('Using custom thumbnail for Instagram: $_thumbnailCloudflareUrl');
        } else {
          // Altrimenti usa il primo frame del video
          requestBody['thumb_offset'] = '0'; // Usa il primo frame come thumbnail
        }
        
        if (!description.isEmpty) {
          requestBody['caption'] = description;
        } else {
          // Instagram può richiedere una caption, aggiungiamo un valore predefinito
          requestBody['caption'] = widget.title;
        }
      }
      
      // Stampa i parametri della richiesta per debug
      print('Parametri richiesta Instagram: ${requestBody.toString()}');
      print('URL API: https://graph.instagram.com/$apiVersion/$userId/media');
      
      // Create Instagram container
      final containerResponse = await http.post(
        Uri.parse('https://graph.instagram.com/$apiVersion/$userId/media'),
        body: requestBody,
      ).timeout(const Duration(seconds: 60));
      
      if (containerResponse.statusCode != 200) {
        print('Risposta errore container: ${containerResponse.body}');
        throw Exception('Errore nella creazione del container Instagram: ${containerResponse.body}');
      }
      
      final containerData = json.decode(containerResponse.body);
      final containerId = containerData['id'];
      
      setState(() {
        _accountStatus[accountId] = 'Checking media status...';
        _accountProgress[accountId] = 0.8; // 80%
      });
      
      // Check container status
      bool isContainerReady = false;
      int maxAttempts = 30;
      int attempt = 0;
      String lastStatus = '';
      
      while (!isContainerReady && attempt < maxAttempts) {
        attempt++;
        
        setState(() {
          _accountStatus[accountId] = 'Media processing (${attempt}/${maxAttempts})...';
          _accountProgress[accountId] = 0.8 + (attempt / maxAttempts * 0.1); // 80-90%
        });
        
        try {
          final statusResponse = await http.get(
            Uri.parse('https://graph.instagram.com/$apiVersion/$containerId')
              .replace(queryParameters: {
                'fields': 'status_code,status',
                'access_token': accessToken,
              }),
          ).timeout(const Duration(seconds: 15));
          
          print('Status response: ${statusResponse.body}');
          
          if (statusResponse.statusCode == 200) {
            final statusData = json.decode(statusResponse.body);
            final status = statusData['status_code'];
            final detailedStatus = statusData['status'] ?? 'N/A';
            
            print('Status container: $status, Detailed: $detailedStatus');
            lastStatus = status;
            
            if (status == 'FINISHED') {
              isContainerReady = true;
              break;
            } else if (status == 'ERROR') {
              // Se errore persiste per più di 10 tentativi, interrompi
              if (attempt > 10) {
                throw Exception('Error in media processing: $status, Details: $detailedStatus');
              }
              // Altrimenti continua a provare
              await Future.delayed(Duration(seconds: 3));
              continue;
            }
          }
          
          await Future.delayed(Duration(seconds: 2));
        } catch (e) {
          print('Errore nel controllo dello stato: $e');
          
          // Se errore persiste per più di 15 tentativi, interrompi
          if (attempt > 15) {
            throw e;
          }
          
          await Future.delayed(Duration(seconds: 2));
        }
      }
      
      // Se dopo tutti i tentativi lo stato è ancora ERROR, prova comunque a pubblicare
      if (lastStatus == 'ERROR' && attempt >= maxAttempts) {
        print('WARNING: The container status remains ERROR after $maxAttempts attempts');
        print('Attempting to publish anyway...');
      } else if (!isContainerReady) {
        throw Exception('Timeout in media processing after $maxAttempts attempts');
      }
      
      setState(() {
        _accountStatus[accountId] = 'Publishing to Instagram...';
        _accountProgress[accountId] = 0.9; // 90%
      });
      
      // Publish to Instagram
      final publishResponse = await http.post(
        Uri.parse('https://graph.instagram.com/$apiVersion/$userId/media_publish'),
        body: {
          'access_token': accessToken,
          'creation_id': containerId,
        },
      ).timeout(const Duration(seconds: 60));
      
      print('Publish response: ${publishResponse.body}');
      
      if (publishResponse.statusCode != 200) {
        throw Exception('Error publishing to Instagram: ${publishResponse.body}');
      }
      
      // Parse the response to get the media_id
      final publishData = json.decode(publishResponse.body);
      final mediaId = publishData['id'];
      
      // Save the media_id for this account (Instagram uses media_id, not post_id)
      if (mediaId != null) {
        _accountMediaIds[accountId] = mediaId.toString();
        print('Instagram media_id saved for account $accountId: $mediaId');
      }

      // Success!
      setState(() {
        _accountProgress[accountId] = 1.0; // 100%
        _accountStatus[accountId] = 'Uploaded successfully to Instagram!';
        _accountComplete[accountId] = true;
        _accountError[accountId] = null;
        _completedPlatforms.add('Instagram');
      });
      
    } catch (e) {
      final raw = e.toString();
      String errorMessage =
          'Something went wrong while publishing to Instagram. Please try again in a few minutes.';

      if (raw.contains('Utente non autenticato') ||
          raw.contains('token') ||
          raw.contains('Token di accesso') ||
          raw.toLowerCase().contains('auth')) {
        errorMessage =
            'Instagram authentication error. Please reconnect this Instagram account from the Social Accounts page, then try again.';
      } else if (raw.contains('Account Instagram non trovato')) {
        errorMessage =
            'Instagram account not found. Please remove and reconnect this Instagram account, then try again.';
      } else if (raw.contains('URL del file non accessibile') ||
          raw.contains('accessibile') ||
          raw.toLowerCase().contains('accessible')) {
        errorMessage =
            'Instagram could not reach the media URL. Please check your connection and try the upload again.';
      } else if (raw.toLowerCase().contains('timeout') ||
          raw.toLowerCase().contains('timed out')) {
        errorMessage =
            'Instagram took too long to process this media. Please try again, preferably with a smaller or shorter file.';
      }

      setState(() {
        _accountError[accountId] = errorMessage;
        _accountComplete[accountId] = true; // Mark as complete with error
        _accountProgress[accountId] = 1.0; // 100% (with error)
        // Add to completed platforms with error to show in progress circle
        _completedPlatforms.add('Instagram');
      });
    }
  }

  // Upload di un carosello Instagram (più media in un unico post) per un account
  Future<void> _uploadInstagramCarousel({
    required String accountId,
    required String userId,
    required String accessToken,
    required String description,
    required String contentType,
  }) async {
    try {
      // Limita comunque a massimo 10 media come da documentazione ufficiale
      final int maxItems = 10;
      final int totalItems = _cloudflareUrls.length.clamp(1, maxItems);

      if (totalItems < 2) {
        print('Carosello richiesto ma numero di media < 2, fallback al flusso singolo.');
        return;
      }

      setState(() {
        _accountStatus[accountId] = 'Preparing Instagram carousel...';
        _accountProgress[accountId] = 0.65;
      });

      const apiVersion = 'v18.0';
      final List<String> childrenIds = [];

      // 1) Crea i container per tutti i media (children)
      for (int i = 0; i < totalItems && i < _mediaFiles.length; i++) {
        try {
          final String baseUrl =
              i < _cloudflareUrls.length ? _cloudflareUrls[i] : (_cloudflareUrl ?? '');
          if (baseUrl.isEmpty) {
            print('URL Cloudflare mancante per media indice $i, salto.');
            continue;
          }

          bool isImage = i < _isImageFiles.length ? _isImageFiles[i] : widget.isImageFile;

          // Normalizza URL nel formato pub-[accountId].r2.dev
          String cloudflareUrl = baseUrl;
          if (!cloudflareUrl.contains('pub-') || !cloudflareUrl.contains('.r2.dev')) {
            final String fileName =
                cloudflareUrl.contains('/') ? cloudflareUrl.split('/').last : cloudflareUrl;
            const String cloudflareAccountId = '3d945eb681944ec5965fecf275e41a9b';
            cloudflareUrl = 'https://pub-$cloudflareAccountId.r2.dev/$fileName';
          }

          // Per le immagini, ridimensiona prima il file locale e ri-carica su Cloudflare
          String finalMediaUrl = cloudflareUrl;
          if (isImage) {
            try {
              final File imageFile = _mediaFiles[i];
              final resized = await _resizeImageForInstagram(imageFile);
              if (resized != null) {
                final resizedUrl = await _uploadResizedImageToCloudflare(resized);
                if (resizedUrl != null) {
                  finalMediaUrl = resizedUrl;
                }
              }
            } catch (e) {
              print('Errore nel resize del media carosello $i per Instagram: $e');
            }
          }

          // Verifica accessibilità
          final bool accessible = await _verifyFileAccessibility(finalMediaUrl);
          if (!accessible) {
            print('Media carosello $i non accessibile pubblicamente, salto questo media');
            continue;
          }

          final Map<String, String> childBody = {
            'access_token': accessToken,
            'is_carousel_item': 'true',
          };

          if (isImage) {
            childBody['image_url'] = finalMediaUrl;
          } else {
            childBody['video_url'] = finalMediaUrl;
          }

          print('Creating Instagram carousel child (index=$i) with body: $childBody');

          final childResponse = await http
              .post(
                Uri.parse('https://graph.instagram.com/$apiVersion/$userId/media'),
                body: childBody,
              )
              .timeout(const Duration(seconds: 60));

          if (childResponse.statusCode != 200) {
            print('Errore creazione container child Instagram idx=$i: ${childResponse.body}');
            continue;
          }

          final childData = json.decode(childResponse.body);
          final childId = childData['id'];
          if (childId == null) {
            print('Nessun childId per media carosello idx=$i');
            continue;
          }

          childrenIds.add(childId.toString());

          setState(() {
            _accountStatus[accountId] = 'Preparing media ${i + 1}/$totalItems...';
            _accountProgress[accountId] = 0.65 + ((i + 1) / totalItems) * 0.15; // 65–80%
          });
        } catch (e) {
          print('Errore generale creazione child carosello idx=$i per account $accountId: $e');
        }
      }

      if (childrenIds.length < 2) {
        print('Numero di children validi < 2, impossibile creare un carosello.');
        throw Exception('Numero insufficiente di media validi per carosello.');
      }

      // 2) Crea il container carosello principale
      final String childrenParam = childrenIds.join(',');

      setState(() {
        _accountStatus[accountId] = 'Creating Instagram carousel container...';
        _accountProgress[accountId] = 0.8;
      });

      final Map<String, String> carouselBody = {
        'access_token': accessToken,
        'caption': description.isNotEmpty ? description : widget.title,
        'media_type': 'CAROUSEL',
        'children': childrenParam,
      };

      final carouselResponse = await http
          .post(
            Uri.parse('https://graph.instagram.com/$apiVersion/$userId/media'),
            body: carouselBody,
          )
          .timeout(const Duration(seconds: 60));

      if (carouselResponse.statusCode != 200) {
        print('Errore creazione container carosello Instagram: ${carouselResponse.body}');
        throw Exception('Errore nella creazione del container carosello Instagram.');
      }

      final carouselData = json.decode(carouselResponse.body);
      final String? carouselId = carouselData['id']?.toString();
      if (carouselId == null || carouselId.isEmpty) {
        throw Exception('ID container carosello non valido.');
      }

      // 3) Polling stato carosello
      bool isCarouselReady = false;
      int attempt = 0;
      const int maxAttempts = 30;
      String lastStatus = '';

      while (!isCarouselReady && attempt < maxAttempts) {
        attempt++;

        setState(() {
          _accountStatus[accountId] =
              'Carousel processing (${attempt.toString()}/$maxAttempts)...';
          _accountProgress[accountId] = 0.8 + (attempt / maxAttempts * 0.1); // 80–90%
        });

        try {
          final statusResponse = await http
              .get(
                Uri.parse('https://graph.instagram.com/$apiVersion/$carouselId').replace(
                  queryParameters: {
                    'fields': 'status_code,status',
                    'access_token': accessToken,
                  },
                ),
              )
              .timeout(const Duration(seconds: 15));

          if (statusResponse.statusCode == 200) {
            final statusData = json.decode(statusResponse.body);
            final status = statusData['status_code'];
            final detailed = statusData['status'] ?? 'N/A';
            lastStatus = status ?? '';
            print('Status container carosello: $status, detailed=$detailed');

            if (status == 'FINISHED') {
              isCarouselReady = true;
              break;
            } else if (status == 'ERROR') {
              if (attempt > 10) {
                throw Exception('Errore nel processamento carosello: $detailed');
              }
            }
          }
        } catch (e) {
          print('Errore polling container carosello: $e');
          if (attempt > 15) {
            throw e;
          }
        }

        await Future.delayed(const Duration(seconds: 2));
      }

      if (!isCarouselReady && lastStatus != 'ERROR') {
        throw Exception('Timeout nel processamento del carosello dopo $maxAttempts tentativi.');
      }

      // 4) Pubblica il carosello
      setState(() {
        _accountStatus[accountId] = 'Publishing Instagram carousel...';
        _accountProgress[accountId] = 0.9;
      });

      final publishResponse = await http
          .post(
            Uri.parse('https://graph.instagram.com/$apiVersion/$userId/media_publish'),
            body: {
              'access_token': accessToken,
              'creation_id': carouselId,
            },
          )
          .timeout(const Duration(seconds: 60));

      print('Publish response carosello: ${publishResponse.body}');

      if (publishResponse.statusCode != 200) {
        throw Exception('Errore nella pubblicazione del carosello: ${publishResponse.body}');
      }

      final publishData = json.decode(publishResponse.body);
      final String? mediaId = publishData['id']?.toString();
      if (mediaId != null && mediaId.isNotEmpty) {
        _accountMediaIds[accountId] = mediaId;
        print('Instagram carousel media_id saved for account $accountId: $mediaId');
      }

      setState(() {
        _accountProgress[accountId] = 1.0; // 100%
        _accountStatus[accountId] = 'Uploaded Instagram carousel successfully!';
        _accountComplete[accountId] = true;
        _accountError[accountId] = null;
        _completedPlatforms.add('Instagram');
      });
    } catch (e) {
      print('Errore upload carosello Instagram per account $accountId: $e');
      setState(() {
        _accountError[accountId] =
            'Instagram carousel upload failed. Please try again. If this keeps happening, try with fewer media items or different files.';
        _accountComplete[accountId] = true;
        _accountProgress[accountId] = 1.0;
        _completedPlatforms.add('Instagram');
      });
    }
  }
  
  // Upload to YouTube using the Cloudflare URL
  Future<void> _uploadToYouTube({
    required Map<String, dynamic> account,
    required String description,
    required String title,
  }) async {
    final String accountId = account['id'];
    
    if (_cloudflareUrl == null) {
      setState(() {
        _accountError[accountId] =
            'File URL is not available. Please restart this upload and try again.';
        _accountComplete[accountId] = true; // Mark as complete with error
      });
      return;
    }
    
    // Create a more gradual progress animation for YouTube
    for (int i = 1; i <= 5; i++) {
      if (!mounted) break;
    
    setState(() {
        double progressStep = 0.5 + (i * 0.02); // Progress from 50% to 60% in steps
        _accountProgress[accountId] = progressStep;
      _accountStatus[accountId] = 'Preparing upload to YouTube...';
      });
      
      await Future.delayed(Duration(milliseconds: 100));
    }
    
    setState(() {
      _accountStatus[accountId] = 'Preparing upload to YouTube...';
      _accountProgress[accountId] = 0.6; // Match Instagram progression for consistency
    });
    
    try {
      // Get YouTube account data
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Utente non autenticato');
      }
      
      // Get account data from Firebase
      final accountSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(currentUser.uid)
          .child('youtube')
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        throw Exception('Account YouTube non trovato');
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      
      // Initialize Google Sign-In
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: [
          'https://www.googleapis.com/auth/youtube.upload',
          'https://www.googleapis.com/auth/youtube.readonly',
          'https://www.googleapis.com/auth/youtube'
        ],
        clientId: '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com',
        signInOption: SignInOption.standard,
      );
      
      setState(() {
        _accountStatus[accountId] = 'Authentication with Google...';
        _accountProgress[accountId] = 0.35;
      });
      
      // Sign in with Google
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Accesso Google annullato');
      }
      
      // Get authentication details
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      if (googleAuth.accessToken == null) {
        throw Exception('Impossibile ottenere il token di accesso');
      }
      
      // Prepare video metadata with user-selected options
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
          'title': title, // Use the title passed as parameter
          'description': description,
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
      setState(() {
        _accountStatus[accountId] = 'Uploading video to YouTube...';
        _accountProgress[accountId] = 0.4; // 40%
      });
      
      // Implement retry mechanism for video upload
      int uploadRetries = 0;
      const maxUploadRetries = 3;
      http.Response? uploadResponse;
      
      while (uploadRetries < maxUploadRetries && (uploadResponse == null || uploadResponse.statusCode != 200)) {
        try {
          // If we have a Cloudflare URL, we can use it directly
          if (_cloudflareUrl != null && !widget.isImageFile) {
            // Verify cloudflare URL is accessible
            bool isAccessible = await _verifyFileAccessibility(_cloudflareUrl!);
            if (!isAccessible) {
              throw Exception('Video URL not accessible publicly');
            }
            
            setState(() {
              _accountStatus[accountId] = 'Uploading video from remote URL...';
            });
            
            // TODO: Direct URL uploads are complex with YouTube API
            // For now, we'll read the file and upload it directly
          }
          
          setState(() {
            _accountStatus[accountId] = 'Uploading video to YouTube...';
          });
          
          uploadResponse = await http.post(
            Uri.parse('https://www.googleapis.com/upload/youtube/v3/videos?part=snippet,status'),
            headers: {
              'Authorization': 'Bearer ${googleAuth.accessToken}',
              'Content-Type': 'application/octet-stream',
              'X-Upload-Content-Type': 'video/*',
              'X-Upload-Content-Length': widget.mediaFile.lengthSync().toString(),
            },
            body: await widget.mediaFile.readAsBytes(),
          ).timeout(
            const Duration(minutes: 5),
            onTimeout: () => throw TimeoutException('Upload request timed out. Check your internet connection.'),
          );
          
          if (uploadResponse.statusCode != 200) {
            throw Exception('Error uploading video: ${uploadResponse.body}');
          }
        } catch (e) {
          print('YouTube upload error (attempt ${uploadRetries + 1}): $e');
          uploadRetries++;
          
          if (uploadRetries < maxUploadRetries) {
            setState(() {
              _accountStatus[accountId] = 'Upload retry (${uploadRetries + 1}/$maxUploadRetries)...';
              _accountProgress[accountId] = 0.4 + (uploadRetries * 0.05); // 40-50%
            });
            await Future.delayed(Duration(seconds: 3 * uploadRetries)); // Exponential backoff
          } else {
            rethrow;
          }
        }
      }
      
      if (uploadResponse == null || uploadResponse.statusCode != 200) {
        throw Exception('Error uploading video after $maxUploadRetries attempts');
      }
      
      final videoData = json.decode(uploadResponse.body);
      final videoId = videoData['id'];
      
      // Save the post_id (video_id) for this account
      if (videoId != null) {
        _accountPostIds[accountId] = videoId.toString();
        print('YouTube post_id saved for account $accountId: $videoId');
      }
      
      setState(() {
        _accountStatus[accountId] = 'Updating video metadata...';
        _accountProgress[accountId] = 0.8; // 80%
      });
      
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
            onTimeout: () => throw TimeoutException('Richiesta di aggiornamento metadati scaduta.'),
          );
          
          if (metadataResponse.statusCode != 200) {
            throw Exception('Error updating video metadata: ${metadataResponse.body}');
          }
        } catch (e) {
          print('YouTube metadata update error (attempt ${metadataRetries + 1}): $e');
          metadataRetries++;
          
          if (metadataRetries < maxMetadataRetries) {
            setState(() {
              _accountStatus[accountId] = 'Updating video metadata (${metadataRetries + 1}/$maxMetadataRetries)...';
              _accountProgress[accountId] = 0.8 + (metadataRetries * 0.03); // 80-89%
            });
            await Future.delayed(Duration(seconds: 2 * metadataRetries)); // Exponential backoff
          } else {
            rethrow;
          }
        }
      }
      
      if (metadataResponse == null || metadataResponse.statusCode != 200) {
        throw Exception('Errore nell\'aggiornamento dei metadati del video dopo $maxMetadataRetries tentativi');
      }

      // Upload custom thumbnail if available
      if (widget.youtubeThumbnailFile != null) {
        final file = widget.youtubeThumbnailFile!;
        final bytes = await file.readAsBytes();
        final fileSize = bytes.length;
        final mimeType = file.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
        print('***YOUTUBE THUMBNAIL*** instagram_upload_page.dart: path: \'${file.path}\', size: ${fileSize} bytes, mime: $mimeType');
        if (fileSize > 2 * 1024 * 1024) {
          print('***YOUTUBE THUMBNAIL ERROR***: Thumbnail file exceeds 2MB, cannot upload.');
          setState(() {
            _accountStatus[accountId] = 'Thumbnail too large (>2MB), not uploaded!';
            _accountProgress[accountId] = 0.95;
          });
        } else if (!(mimeType == 'image/jpeg' || mimeType == 'image/png')) {
          print('***YOUTUBE THUMBNAIL ERROR***: Thumbnail must be JPEG or PNG.');
          setState(() {
            _accountStatus[accountId] = 'Thumbnail must be JPEG or PNG!';
            _accountProgress[accountId] = 0.95;
          });
        } else {
          try {
            setState(() {
              _accountStatus[accountId] = 'Uploading custom thumbnail...';
              _accountProgress[accountId] = 0.9; // 90%
            });
            print('Uploading custom thumbnail for YouTube video: $videoId');
            final thumbnailResponse = await http.post(
              Uri.parse('https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=$videoId'),
              headers: {
                'Authorization': 'Bearer ${googleAuth.accessToken}',
                'Content-Type': mimeType,
              },
              body: bytes,
            ).timeout(
              const Duration(seconds: 30),
              onTimeout: () => throw TimeoutException('Thumbnail upload request timed out.'),
            );
            if (thumbnailResponse.statusCode == 200) {
              setState(() {
                _accountStatus[accountId] = 'Custom thumbnail uploaded successfully!';
                _accountProgress[accountId] = 0.95; // 95%
              });
              print('Custom thumbnail uploaded successfully to YouTube!');
            } else {
              print('Warning: Failed to upload custom thumbnail: \'${thumbnailResponse.body}\'');
              setState(() {
                _accountStatus[accountId] = 'Warning: Thumbnail upload failed, but video is ready!';
                _accountProgress[accountId] = 0.95; // 95%
              });
            }
          } catch (e) {
            print('Warning: Error uploading custom thumbnail: $e');
            setState(() {
              _accountStatus[accountId] = 'Warning: Thumbnail upload failed, but video is ready!';
              _accountProgress[accountId] = 0.95; // 95%
            });
          }
        }
      }
      
      // Update account data with the new video
      await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(currentUser.uid)
          .child('youtube')
          .child(accountId)
          .update({
        'video_count': (accountData['video_count'] ?? 0) + 1,
        'last_sync': DateTime.now().millisecondsSinceEpoch,
      });
      
      // Success!
      setState(() {
        _accountProgress[accountId] = 1.0; // 100%
        _accountStatus[accountId] = 'Uploaded successfully to YouTube!';
        _accountComplete[accountId] = true;
        _accountError[accountId] = null;
        _completedPlatforms.add('YouTube');
      });
      
    } catch (e) {
      print('YouTube upload error: $e');
      
      // Provide more specific error messages based on the error type
      String errorMessage =
          'Something went wrong while publishing to YouTube. Please try again. If the problem persists, check your connection or try a smaller file.';
      
      if (e.toString().contains('YouTube account not found') ||
          e.toString().contains('token')) {
        errorMessage =
            'YouTube authentication error. Please reconnect this YouTube account from the Social Accounts page, then try again.';
      } else if (e.toString().toLowerCase().contains('timeout')) {
        errorMessage =
            'Upload to YouTube timed out. Please check your internet connection and try again.';
      } else if (e.toString().toLowerCase().contains('quota')) {
        errorMessage =
            'Your YouTube daily quota appears to be exceeded. Please wait a few hours or use a different Google account.';
      }
      
      setState(() {
        _accountError[accountId] = errorMessage;
        _accountComplete[accountId] = true; // Mark as complete with error
        _accountProgress[accountId] = 1.0; // 100% (with error)
        _completedPlatforms.add('YouTube');
      });
    }
  }
  
  // Upload to Twitter using the Cloudflare URL
  Future<void> _uploadToTwitter({
    required Map<String, dynamic> account,
    required String description
  }) async {
    final String accountId = account['id'];
    
    if (_cloudflareUrl == null) {
      setState(() {
        _accountError[accountId] =
            'File URL is not available. Please restart this upload and try again.';
        _accountComplete[accountId] = true; // Mark as complete with error
      });
      return;
    }
    
    setState(() {
      _accountStatus[accountId] = 'Preparing upload to Twitter...';
      _accountProgress[accountId] = 0.6; // 60%
    });
    
    try {
      // Get Twitter account data
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Utente non autenticato');
      }
      
      // Get account data from Firebase
      final accountSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        throw Exception('Account Twitter non trovato');
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token'];
      final accessTokenSecret = accountData['access_token_secret'] ?? accountData['token_secret'];
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Token di accesso Twitter non trovato');
      }
      
      if (accessTokenSecret == null || accessTokenSecret.isEmpty) {
        throw Exception('Token secret di accesso Twitter non trovato');
      }
      
      setState(() {
        _accountStatus[accountId] = 'Initializing Twitter API...';
        _accountProgress[accountId] = 0.65; // 65%
      });
      
      // Initialize Twitter API
      final twitter = v2.TwitterApi(
        bearerToken: '',  // Empty bearer token to force OAuth 1.0a
        oauthTokens: v2.OAuthTokens(
          consumerKey: 'sTn3lkEWn47KiQl41zfGhjYb4',
          consumerSecret: 'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA',
          accessToken: accessToken,
          accessTokenSecret: accessTokenSecret,
        ),
        retryConfig: v2.RetryConfig(
          maxAttempts: 3,
          onExecute: (event) => print('Retrying Twitter API call... [${event.retryCount} times]'),
        ),
        timeout: const Duration(seconds: 60),
      );
      
      setState(() {
        _accountStatus[accountId] = 'Uploading file to Twitter...';
        _accountProgress[accountId] = 0.7; // 70%
      });
      
      // Upload the media to Twitter
      final uploadResponse = await twitter.media.uploadMedia(
        file: widget.mediaFile,
        onProgress: (event) {
          switch (event.state) {
            case v2.UploadState.preparing:
              setState(() {
                _accountStatus[accountId] = 'Preparing upload to Twitter...';
                _accountProgress[accountId] = 0.75; // 75%
              });
              break;
            case v2.UploadState.inProgress:
              setState(() {
                _accountStatus[accountId] = 'Upload in progress: ${event.progress}%';
                // Scale progress from 75% to 85%
                _accountProgress[accountId] = 0.75 + (event.progress / 100) * 0.1;
              });
              break;
            case v2.UploadState.completed:
              setState(() {
                _accountStatus[accountId] = 'Upload completed, creating tweet...';
                _accountProgress[accountId] = 0.85; // 85%
              });
              break;
          }
        },
      );
      
      if (uploadResponse.data == null) {
        throw Exception('Errore durante l\'upload del media su Twitter');
      }
      
      setState(() {
        _accountStatus[accountId] = 'Creating tweet...';
        _accountProgress[accountId] = 0.9; // 90%
      });
      
      // Create the tweet with the uploaded media
      final tweet = await twitter.tweets.createTweet(
        text: description,
        media: v2.TweetMediaParam(
          mediaIds: [uploadResponse.data!.id],
        ),
      );
      
      if (tweet.data == null) {
        throw Exception('Errore durante la creazione del tweet');
      }
      
      // Save the post_id (tweet_id) for this account
      final tweetId = tweet.data!.id;
      if (tweetId != null) {
        _accountPostIds[accountId] = tweetId.toString();
        print('Twitter post_id saved for account $accountId: $tweetId');
      }
      
      // Success!
      setState(() {
        _accountProgress[accountId] = 1.0; // 100%
        _accountStatus[accountId] = 'Uploaded successfully to Twitter!';
        _accountComplete[accountId] = true;
        _accountError[accountId] = null;
        _completedPlatforms.add('Twitter');
      });
      
    } catch (e) {
      print('Twitter upload error: $e');
      
      // Provide more specific error messages based on the error type
      String errorMessage =
          'Something went wrong while publishing to Twitter. Please try again.';
      
      if (e.toString().contains('Twitter account not found') ||
          e.toString().contains('token')) {
        errorMessage =
            'Twitter authentication error. Please reconnect this Twitter account from the Social Accounts page, then try again.';
      } else if (e.toString().toLowerCase().contains('timeout')) {
        errorMessage =
            'Upload to Twitter timed out. Please check your internet connection and try again.';
      } else if (e.toString().contains('media upload failed')) {
        errorMessage =
            'Twitter could not process this media. Try converting the video to a different format or a smaller size, then upload again.';
      }
      
      setState(() {
        _accountError[accountId] = errorMessage;
        _accountComplete[accountId] = true; // Mark as complete with error
        _accountProgress[accountId] = 1.0; // 100% (with error)
        _completedPlatforms.add('Twitter');
      });
    }
  }
  
  // Upload to Threads using the Cloudflare URL
  Future<void> _uploadToThreads({
    required Map<String, dynamic> account,
    required String description
  }) async {
    final String accountId = account['id'];
    
    if (_cloudflareUrl == null) {
      setState(() {
        _accountError[accountId] =
            'File URL is not available. Please restart this upload and try again.';
        _accountComplete[accountId] = true; // Mark as complete with error
      });
      return;
    }
    
    setState(() {
      _accountStatus[accountId] = 'Preparing upload to Threads...';
      _accountProgress[accountId] = 0.6; // 60%
    });
    
    try {
      // Get Threads account data
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Utente non autenticato');
      }
      
      // Get account data from Firebase
      final accountSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('threads')
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        throw Exception('Account Threads non trovato');
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token'];
      final userId = accountData['user_id'] ?? accountId;
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Token di accesso Threads non trovato');
      }
      
      // Verifica l'accessibilità dell'URL prima di procedere
      setState(() {
        _accountStatus[accountId] = 'Checking media accessibility...';
        _accountProgress[accountId] = 0.65;
      });
      
      // Ensure the URL is in a format Threads can access
      // Threads might need a specific URL format
      String threadsMediaUrl = _cloudflareUrl!;
      
      // Try to convert to a domain that Threads can access if needed
      if (!_cloudflareUrl!.contains('viralyst.online')) {
        try {
          final uri = Uri.parse(_cloudflareUrl!);
          threadsMediaUrl = 'https://viralyst.online${uri.path}';
          print('URL convertito in formato accessibile a Threads: $threadsMediaUrl');
        } catch (e) {
          print('Errore nella conversione URL: $e');
          // Keep original URL if conversion fails
          threadsMediaUrl = _cloudflareUrl!;
        }
      }
      
      // Verifica l'accessibilità dell'URL
      bool isAccessible = await _verifyFileAccessibility(threadsMediaUrl);
      
      if (!isAccessible) {
        print('ATTENZIONE: URL del file non accessibile pubblicamente: $threadsMediaUrl');
        setState(() {
      _accountStatus[accountId] = 'The media may not be publicly accessible, attempting anyway...';
          _accountProgress[accountId] = 0.7;
        });
      } else {
        setState(() {
      _accountStatus[accountId] = 'Media accessible, creating Threads container...';
          _accountProgress[accountId] = 0.7;
        });
      }
      
      // Step 1: Create a media container for Threads
      setState(() {
    _accountStatus[accountId] = 'Creating Threads container...';
        _accountProgress[accountId] = 0.75; // 75%
      });
      
      final Map<String, String> containerParams = {
        'access_token': accessToken,
        'text': description,
        'media_type': widget.isImageFile ? 'IMAGE' : 'VIDEO',
      };
      
      // Add appropriate URL based on media type
      if (widget.isImageFile) {
        containerParams['image_url'] = threadsMediaUrl;
      } else {
        containerParams['video_url'] = threadsMediaUrl;
      }
      
      final containerResponse = await http.post(
        Uri.parse('https://graph.threads.net/v1.0/$userId/threads'),
        body: containerParams,
      ).timeout(Duration(seconds: 60));
      
      if (containerResponse.statusCode != 200) {
        throw Exception('Errore nella creazione del container Threads: ${containerResponse.body}');
      }
      
      final containerData = json.decode(containerResponse.body);
      final containerId = containerData['id'];
      
      if (containerId == null || containerId.isEmpty) {
        throw Exception('Failed to get container ID from Threads response');
      }
      
      // Step 2: Wait before publishing as recommended by Threads API documentation
      setState(() {
        _accountStatus[accountId] = 'Waiting for media processing (30s)...';
        _accountProgress[accountId] = 0.8; // 80%
      });
      
      // Threads API recommends waiting about 30 seconds before publishing
      for (int i = 0; i < 30; i++) {
        if (!mounted) break;
        
        if (i % 5 == 0) { // Update message every 5 seconds
          setState(() {
            _accountStatus[accountId] = 'Waiting for media processing (${30-i}s)...';
            _accountProgress[accountId] = 0.8 + (i / 30) * 0.1; // 80-90%
          });
        }
        
        await Future.delayed(Duration(seconds: 1));
      }
      
      // Step 3: Publish the container
      setState(() {
        _accountStatus[accountId] = 'Publishing to Threads...';
        _accountProgress[accountId] = 0.9; // 90%
      });
      
      final publishResponse = await http.post(
        Uri.parse('https://graph.threads.net/v1.0/$userId/threads_publish'),
        body: {
          'access_token': accessToken,
          'creation_id': containerId,
        },
      ).timeout(Duration(seconds: 60));
      
      if (publishResponse.statusCode != 200) {
        throw Exception('Error publishing to Threads: ${publishResponse.body}');
      }
      
      // Parse the response to get the post_id
      final publishData = json.decode(publishResponse.body);
      final postId = publishData['id'];
      
      // Save the post_id for this account (Threads uses post_id, not media_id)
      if (postId != null) {
        _accountPostIds[accountId] = postId.toString();
        print('Threads post_id saved for account $accountId: $postId');
      }
      
      // Success!
      setState(() {
        _accountProgress[accountId] = 1.0; // 100%
        _accountStatus[accountId] = 'Uploaded successfully to Threads!';
        _accountComplete[accountId] = true;
        _accountError[accountId] = null;
        _completedPlatforms.add('Threads');
      });
      
    } catch (e) {
      print('Threads upload error: $e');
      
      // Provide more specific error messages based on the error type
      String errorMessage =
          'Something went wrong while publishing to Threads. Please try again.';
      
      if (e.toString().contains('Threads account not found') ||
          e.toString().contains('token')) {
        errorMessage =
            'Threads authentication error. Please reconnect this Threads account from the Social Accounts page, then try again.';
      } else if (e.toString().toLowerCase().contains('timeout')) {
        errorMessage =
            'Upload to Threads timed out. Please check your internet connection and try again.';
      } else if (e.toString().contains('container') ||
          e.toString().contains('media')) {
        errorMessage =
            'Threads could not process this media. Try a different file (format or size) and upload again.';
      }
      
      setState(() {
        _accountError[accountId] = errorMessage;
        _accountComplete[accountId] = true; // Mark as complete with error
        _accountProgress[accountId] = 1.0; // 100% (with error)
        _completedPlatforms.add('Threads');
      });
    }
  }
  
  // Upload to TikTok using the Cloudflare URL
  Future<void> _uploadToTikTok({
    required Map<String, dynamic> account,
    required String description
  }) async {
    final String accountId = account['id'];
    
    if (_cloudflareUrl == null) {
      setState(() {
        _accountError[accountId] =
            'File URL is not available. Please restart this upload and try again.';
        _accountComplete[accountId] = true; // Mark as complete with error
      });
      return;
    }
    
    setState(() {
      _accountStatus[accountId] = 'Preparing upload to TikTok...';
      _accountProgress[accountId] = 0.6; // 60%
    });
    
    try {
      // Get TikTok account data
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Utente non autenticato');
      }
      
      // Get account data from Firebase
      final accountSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(currentUser.uid)
          .child('tiktok')
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        throw Exception('Account TikTok non trovato');
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token'];
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Token di accesso TikTok non trovato');
      }
      
      // Step 1: Query creator info to get privacy level options
      setState(() {
      _accountStatus[accountId] = 'Retrieving creator info...';
        _accountProgress[accountId] = 0.65; // 65%
      });
      
      // Query creator info to get available privacy levels
      final creatorInfoResponse = await http.post(
        Uri.parse('https://open.tiktokapis.com/v2/post/publish/creator_info/query/'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json; charset=UTF-8'
        },
      );
      
      if (creatorInfoResponse.statusCode != 200) {
        throw Exception('Errore nel recupero delle informazioni del creator: ${creatorInfoResponse.body}');
      }
      
      final creatorInfoData = json.decode(creatorInfoResponse.body);
      if (creatorInfoData['error']['code'] != 'ok') {
        throw Exception('Errore API TikTok: ${creatorInfoData['error']['message']}');
      }
      
      // Extract the first privacy level option as default
      final privacyLevelOptions = List<String>.from(creatorInfoData['data']['privacy_level_options'] ?? []);
      
      // Use user-selected privacy level if available, otherwise use default
      String privacyLevel;
      if (widget.tiktokOptions != null && widget.tiktokOptions!.containsKey(accountId)) {
        final userPrivacyLevel = widget.tiktokOptions![accountId]?['privacy_level'];
        if (userPrivacyLevel != null && privacyLevelOptions.contains(userPrivacyLevel)) {
          privacyLevel = userPrivacyLevel;
        } else {
          privacyLevel = privacyLevelOptions.isNotEmpty ? privacyLevelOptions.first : 'PUBLIC_TO_EVERYONE';
        }
      } else {
        privacyLevel = privacyLevelOptions.isNotEmpty ? privacyLevelOptions.first : 'PUBLIC_TO_EVERYONE';
      }
      
      // Step 2: Verify file accessibility
      setState(() {
        _accountStatus[accountId] = 'Checking file accessibility...';
        _accountProgress[accountId] = 0.7; // 70%
      });
      
              // Verifica che l'URL sia accessibile
      bool isAccessible = await _verifyFileAccessibility(_cloudflareUrl!);
      
      if (!isAccessible) {
        print('URL del file non accessibile: $_cloudflareUrl');
        throw Exception('URL del file non accessibile pubblicamente. TikTok richiede URL accessibili.');
      }
      
      // Usa il dominio verificato per TikTok
      final String fileName = _cloudflareUrl!.split('/').last;
      // L'URL originale ha già il prefisso "media_" quindi lo usiamo direttamente
      final String tiktokVideoUrl = 'https://viralyst.online/$fileName';
      print('Usando URL verificato per TikTok: $tiktokVideoUrl');
      
      // Step 3: Initialize content upload
      setState(() {
        _accountStatus[accountId] = 'Initializing upload to TikTok...';
        _accountProgress[accountId] = 0.75; // 75%
      });
      
      // Check if the media is an image
      if (widget.isImageFile) {
        // Initialize photo upload using content API
        final photoUploadResponse = await http.post(
          Uri.parse('https://open.tiktokapis.com/v2/post/publish/content/init/'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json; charset=UTF-8'
          },
          body: json.encode({
            'post_info': {
              'title': widget.platformDescriptions.containsKey('TikTok') &&
                      widget.platformDescriptions['TikTok']!.containsKey('${accountId}_title')
                  ? widget.platformDescriptions['TikTok']!['${accountId}_title']!
                  : widget.title,
              'description': description,
              'privacy_level': privacyLevel,
              'disable_comment': !(widget.tiktokOptions?[accountId]?['allow_comments'] ?? true),
              'auto_add_music': true,
              'commercial_content': widget.tiktokOptions?[accountId]?['commercial_content'] ?? false,
              'own_brand': widget.tiktokOptions?[accountId]?['own_brand'] ?? false,
              'branded_content': widget.tiktokOptions?[accountId]?['branded_content'] ?? false,
            },
            'source_info': {
              'source': 'PULL_FROM_URL',
              'photo_cover_index': 0,
              'photo_images': [tiktokVideoUrl]
            },
            'post_mode': 'DIRECT_POST',
            'media_type': 'PHOTO'
          }),
        );
        
        if (photoUploadResponse.statusCode != 200) {
          throw Exception('Errore nell\'inizializzazione dell\'upload foto su TikTok: ${photoUploadResponse.body}');
        }
        
        final photoUploadData = json.decode(photoUploadResponse.body);
        if (photoUploadData['error']['code'] != 'ok') {
          throw Exception('Errore API TikTok: ${photoUploadData['error']['message']}');
        }
        
        final publishId = photoUploadData['data']['publish_id'];
        
        // Step 4: Check post status
        setState(() {
      _accountStatus[accountId] = 'Monitoring publish status...';
          _accountProgress[accountId] = 0.85; // 85%
        });
        
        bool isPublished = false;
        int attempts = 0;
        const maxAttempts = 20;
        
        while (!isPublished && attempts < maxAttempts) {
          attempts++;
          
          setState(() {
            _accountStatus[accountId] = 'Checking publish status (${attempts}/${maxAttempts})...';
            _accountProgress[accountId] = 0.85 + (attempts / maxAttempts * 0.1); // 85-95%
          });
          
          final statusResponse = await http.post(
            Uri.parse('https://open.tiktokapis.com/v2/post/publish/status/fetch/'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json; charset=UTF-8'
            },
            body: json.encode({
              'publish_id': publishId
            }),
          );
          
          if (statusResponse.statusCode == 200) {
            final statusData = json.decode(statusResponse.body);
            
            if (statusData['error']['code'] == 'ok') {
              final status = statusData['data']['status'];
              
              if (status == 'PUBLISH_COMPLETE') {
                isPublished = true;
                break;
              } else if (status == 'PUBLISH_FAILED') {
                throw Exception('Pubblicazione fallita su TikTok: ${statusData['data']['error_code']} - ${statusData['data']['error_message']}');
              }
            }
          }
          
          // Wait before checking again
          await Future.delayed(Duration(seconds: 2));
        }
        
        if (!isPublished) {
          throw Exception('Timeout nella pubblicazione su TikTok dopo $maxAttempts tentativi');
        }
        
        // Save the post_id (publish_id) for this account
        if (publishId != null) {
          _accountPostIds[accountId] = publishId.toString();
          print('TikTok post_id saved for account $accountId: $publishId');
        }
      } else {
        // Handle video uploads
        final videoUploadResponse = await http.post(
          Uri.parse('https://open.tiktokapis.com/v2/post/publish/video/init/'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json; charset=UTF-8'
          },
          body: json.encode({
            'post_info': {
              'title': description,
              'privacy_level': privacyLevel,
              'disable_duet': !(widget.tiktokOptions?[accountId]?['allow_duets'] ?? true),
              'disable_comment': !(widget.tiktokOptions?[accountId]?['allow_comments'] ?? true),
              'disable_stitch': !(widget.tiktokOptions?[accountId]?['allow_stitch'] ?? true),
              'video_cover_timestamp_ms': 1000,
              'commercial_content': widget.tiktokOptions?[accountId]?['commercial_content'] ?? false,
              'own_brand': widget.tiktokOptions?[accountId]?['own_brand'] ?? false,
              'branded_content': widget.tiktokOptions?[accountId]?['branded_content'] ?? false,
            },
            'source_info': {
              'source': 'PULL_FROM_URL',
              'video_url': tiktokVideoUrl
            }
          }),
        );
        
        if (videoUploadResponse.statusCode != 200) {
          throw Exception('Errore nell\'inizializzazione dell\'upload video su TikTok: ${videoUploadResponse.body}');
        }
        
        final videoUploadData = json.decode(videoUploadResponse.body);
        if (videoUploadData['error']['code'] != 'ok') {
          throw Exception('Errore API TikTok: ${videoUploadData['error']['message']}');
        }
        
        final publishId = videoUploadData['data']['publish_id'];
        
        // Step 4: Check post status
        setState(() {
      _accountStatus[accountId] = 'Monitoring publish status...';
          _accountProgress[accountId] = 0.85; // 85%
        });
        
        bool isPublished = false;
        int attempts = 0;
        const maxAttempts = 30;
        
        while (!isPublished && attempts < maxAttempts) {
          attempts++;
          
          setState(() {
            _accountStatus[accountId] = 'Checking publish status (${attempts}/${maxAttempts})...';
            _accountProgress[accountId] = 0.85 + (attempts / maxAttempts * 0.1); // 85-95%
          });
          
          final statusResponse = await http.post(
            Uri.parse('https://open.tiktokapis.com/v2/post/publish/status/fetch/'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json; charset=UTF-8'
            },
            body: json.encode({
              'publish_id': publishId
            }),
          );
          
          if (statusResponse.statusCode == 200) {
            final statusData = json.decode(statusResponse.body);
            
            if (statusData['error']['code'] == 'ok') {
              final status = statusData['data']['status'];
              
              if (status == 'PUBLISH_COMPLETE') {
                isPublished = true;
                break;
              } else if (status == 'PUBLISH_FAILED') {
                throw Exception('Pubblicazione fallita su TikTok: ${statusData['data']['error_code']} - ${statusData['data']['error_message']}');
              }
            }
          }
          
          // Wait before checking again
          await Future.delayed(Duration(seconds: 3));
        }
        
        if (!isPublished) {
          throw Exception('Timeout nella pubblicazione su TikTok dopo $maxAttempts tentativi');
        }
        
        // Save the post_id (publish_id) for this account
        if (publishId != null) {
          _accountPostIds[accountId] = publishId.toString();
          print('TikTok post_id saved for account $accountId: $publishId');
        }
      }
      
      // Success!
      setState(() {
        _accountProgress[accountId] = 1.0; // 100%
        _accountStatus[accountId] = 'Uploaded successfully to TikTok!';
        _accountComplete[accountId] = true;
        _accountError[accountId] = null;
        _completedPlatforms.add('TikTok');
      });
      
    } catch (e) {
      print('TikTok upload error: $e');
      
      // Handle retry if needed
      _tiktokUploadAttempts[accountId] = (_tiktokUploadAttempts[accountId] ?? 0) + 1;
      
      if (_tiktokUploadAttempts[accountId]! < _maxTikTokAttempts) {
        print('Retrying TikTok upload (attempt ${_tiktokUploadAttempts[accountId]} of $_maxTikTokAttempts)');
        
        setState(() {
      _accountStatus[accountId] = 'Retry attempt ${_tiktokUploadAttempts[accountId]} of $_maxTikTokAttempts...';
          _accountProgress[accountId] = 0.5; // Reset progress for retry
        });
        
        // Wait before retrying
        await Future.delayed(Duration(seconds: 3));
        return _uploadToTikTok(account: account, description: description);
      }
      
      // Provide more specific error messages based on the error type
      String errorMessage =
          'Something went wrong while publishing to TikTok. Please try again.';
      
      if (e.toString().contains('token') ||
          e.toString().contains('autenticazione')) {
        errorMessage =
            'TikTok authentication error. Please reconnect this TikTok account from the Social Accounts page, then try again.';
      } else if (e.toString().contains('accessibilità') ||
          e.toString().contains('accessible')) {
        errorMessage =
            'File URL is not publicly accessible. Please try the upload again. If it keeps failing, wait a few minutes and retry.';
      } else if (e.toString().toLowerCase().contains('timeout')) {
        errorMessage =
            'Upload to TikTok timed out. Please check your internet connection and try again.';
      } else if (e.toString().contains('privacy_level_option_mismatch')) {
        errorMessage =
            'Selected privacy options are not valid for this TikTok account. Open TikTok options for this account and choose a supported privacy level, then try again.';
      } else if (e.toString().contains('unaudited_client')) {
        errorMessage =
            'Your TikTok app must pass the "Content Sharing" audit before public posts can be published. Complete the audit in the TikTok Developer Portal, then try again.';
      }
      
      setState(() {
        _accountError[accountId] = errorMessage;
        _accountComplete[accountId] = true; // Mark as complete with error
        _accountProgress[accountId] = 1.0; // 100% (with error)
        _completedPlatforms.add('TikTok');
      });
      
      // Show specific dialog for unaudited client error
      if (e.toString().contains('unaudited_client')) {
        _showTikTokAuditDialog();
      }
    }
  }
  
  // Function to upload resized image to Cloudflare R2
  Future<String?> _uploadResizedImageToCloudflare(File resizedImageFile) async {
    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Utente non autenticato');
      }
      
      // Cloudflare R2 credentials
      final String accessKeyId = '5e181628bad7dc5481c92c6f3899efd6';
      final String secretKey = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
      final String endpoint = 'https://3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com';
      final String bucketName = 'videos';
      final String accountId = '3d945eb681944ec5965fecf275e41a9b';
      final String region = 'auto';
      
      // Generate a unique filename for the resized image
      final String fileName = 'instagram_resized_${DateTime.now().millisecondsSinceEpoch}_${currentUser.uid}.jpg';
      final String fileKey = fileName;
      
      // Get file bytes and size
      final bytes = await resizedImageFile.readAsBytes();
      final contentLength = bytes.length;
      
      // Calculate SHA-256 hash of content
      final List<int> contentHash = sha256.convert(bytes).bytes;
      final String payloadHash = hex.encode(contentHash);
      
      // Set up request information
      final String httpMethod = 'PUT';
      final String contentType = 'image/jpeg';
      
      // SigV4 requires date in ISO8601 format
      final now = DateTime.now().toUtc();
      final String amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
      final String dateStamp = DateFormat("yyyyMMdd").format(now);
      
      // Host and URI
      final Uri uri = Uri.parse('$endpoint/$bucketName/$fileKey');
      final String host = uri.host;
      
      // Canonical request
      final Map<String, String> headers = {
        'host': host,
        'content-type': contentType,
        'x-amz-content-sha256': payloadHash,
        'x-amz-date': amzDate
      };
      
      String canonicalHeaders = '';
      String signedHeaders = '';
      
      // Sort headers lexicographically
      final sortedHeaderKeys = headers.keys.toList()..sort();
      for (final key in sortedHeaderKeys) {
        canonicalHeaders += '${key.toLowerCase()}:${headers[key]}\n';
        signedHeaders += '${key.toLowerCase()};';
      }
      signedHeaders = signedHeaders.substring(0, signedHeaders.length - 1);
      
      // Canonical request
      final String canonicalUri = '/$bucketName/$fileKey';
      final String canonicalQueryString = '';
      final String canonicalRequest = '$httpMethod\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
      
      // String to sign
      final String algorithm = 'AWS4-HMAC-SHA256';
      final String scope = '$dateStamp/$region/s3/aws4_request';
      final String stringToSign = '$algorithm\n$amzDate\n$scope\n${hex.encode(sha256.convert(utf8.encode(canonicalRequest)).bytes)}';
      
      // Signature
      List<int> getSignatureKey(String key, String dateStamp, String regionName, String serviceName) {
        final kDate = Hmac(sha256, utf8.encode('AWS4$key')).convert(utf8.encode(dateStamp)).bytes;
        final kRegion = Hmac(sha256, kDate).convert(utf8.encode(regionName)).bytes;
        final kService = Hmac(sha256, kRegion).convert(utf8.encode(serviceName)).bytes;
        final kSigning = Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
        return kSigning;
      }
      
      final signingKey = getSignatureKey(secretKey, dateStamp, region, 's3');
      final signature = hex.encode(Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).bytes);
      
      // Authorization header
      final String authorizationHeader = '$algorithm Credential=$accessKeyId/$scope, SignedHeaders=$signedHeaders, Signature=$signature';
      
      // Create request URL
      final String uploadUrl = '$endpoint/$bucketName/$fileKey';
      
      // Create request with headers
      final http.Request request = http.Request('PUT', Uri.parse(uploadUrl));
      request.headers['Host'] = host;
      request.headers['Content-Type'] = contentType;
      request.headers['Content-Length'] = contentLength.toString();
      request.headers['X-Amz-Content-Sha256'] = payloadHash;
      request.headers['X-Amz-Date'] = amzDate;
      request.headers['Authorization'] = authorizationHeader;
      
      // Add file body
      request.bodyBytes = bytes;
      
      // Send the request
      final response = await http.Client().send(request);
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Generate public URL in the correct format
        final String publicUrl = 'https://pub-$accountId.r2.dev/$fileKey';
        
        print('Resized image uploaded successfully to Cloudflare R2');
        print('Resized image URL: $publicUrl');
        
        return publicUrl;
      } else {
        throw Exception('Error uploading resized image to Cloudflare R2: Code ${response.statusCode}, Response: $responseBody');
      }
    } catch (e) {
      print('Error uploading resized image to Cloudflare: $e');
      return null;
    }
  }

  // Function to resize image for Instagram aspect ratio requirements
  Future<File?> _resizeImageForInstagram(File imageFile) async {
    try {
      // Read the original image
      final bytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);
      
      if (originalImage == null) return null;
      
      final originalWidth = originalImage.width;
      final originalHeight = originalImage.height;
      double aspectRatio = originalWidth / originalHeight;
      
      print('Original image dimensions: ${originalWidth}x${originalHeight}, aspect ratio: $aspectRatio');
      
      // Determine which aspect ratio to use (1:1, 4:5, 1.91:1)
      late img.Image resizedImage;
      
      // Option 1: Square aspect ratio (1:1)
      if (aspectRatio >= 0.8 && aspectRatio <= 1.2) {
        // Already close to square, make it perfect 1:1
        final size = math.min(originalWidth, originalHeight);
        resizedImage = img.copyCrop(
          originalImage,
          x: (originalWidth - size) ~/ 2,
          y: (originalHeight - size) ~/ 2,
          width: size,
          height: size,
        );
        print('Resizing to square 1:1');
      }
      // Option 2: Vertical (4:5) - for vertical images
      else if (aspectRatio < 0.8) {
        // Vertical image, adapt to 4:5
        final targetWidth = originalWidth;
        final targetHeight = (targetWidth * 5 / 4).round();
        
        if (targetHeight <= originalHeight) {
          // Image is taller than needed, crop it
          resizedImage = img.copyCrop(
            originalImage,
            x: 0,
            y: (originalHeight - targetHeight) ~/ 2,
            width: targetWidth,
            height: targetHeight,
          );
        } else {
          // Image is too narrow, resize it maintaining 4:5 aspect
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
      // Option 3: Horizontal (1.91:1) - for horizontal images
      else {
        // Horizontal image, adapt to 1.91:1
        final targetHeight = originalHeight;
        final targetWidth = (targetHeight * 1.91).round();
        
        if (targetWidth <= originalWidth) {
          // Image is wider than needed, crop it
          resizedImage = img.copyCrop(
            originalImage,
            x: (originalWidth - targetWidth) ~/ 2,
            y: 0,
            width: targetWidth,
            height: targetHeight,
          );
        } else {
          // Image is too tall, resize it maintaining 1.91:1 aspect
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
      
      // Save the resized image
      final tempDir = await getTemporaryDirectory();
      final newPath = '${tempDir.path}/instagram_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final resizedFile = File(newPath)..writeAsBytesSync(img.encodeJpg(resizedImage, quality: 90));
      
      print('Resized image dimensions: ${resizedImage.width}x${resizedImage.height}, aspect ratio: ${resizedImage.width / resizedImage.height}');
      
      return resizedFile;
    } catch (e) {
      print('Error resizing image for Instagram: $e');
      return null; // Return null in case of error
    }
  }

  // Helper per verificare che un file sia accessibile pubblicamente
  Future<bool> _verifyFileAccessibility(String url) async {
    try {
      print('Verificando accessibilità URL: $url');
      
      // Verificare che l'URL sia nel formato corretto
      if (!url.contains('pub-3d945eb681944ec5965fecf275e41a9b.r2.dev')) {
        print('AVVISO: URL non nel formato pub-3d945eb681944ec5965fecf275e41a9b.r2.dev');
        // Continuiamo comunque con la verifica
      }
      
      // Impostare un timeout più breve per non bloccare il processo di upload
      final response = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 5));
      
      final bool isSuccess = response.statusCode >= 200 && response.statusCode < 400;
      print('Verifica URL $url: Status ${response.statusCode}, Accessibile: $isSuccess');
      
      return isSuccess;
    } catch (e) {
      print('Errore verifica URL $url: $e');
      
      // In caso di errore, proviamo a convertire l'URL al formato R2 pubblico
      // e verifichiamo di nuovo, ma solo se l'URL non è già in quel formato
      if (!url.contains('pub-') && !url.contains('r2.dev')) {
        try {
          // Convert to public R2 format
          final String cloudflareAccountId = '3d945eb681944ec5965fecf275e41a9b';
          
          // Extract the filename from the URL
          final String fileName;
          if (url.contains('/')) {
            fileName = url.split('/').last;
          } else {
            fileName = url;
          }
          
          // Build the URL in the correct format
          String convertedUrl = 'https://pub-$cloudflareAccountId.r2.dev/$fileName';
          print('Tentativo con URL convertito: $convertedUrl');
          
          // Try with the converted URL
          return _verifyFileAccessibility(convertedUrl);
        } catch (conversionError) {
          print('Errore nella conversione URL: $conversionError');
        }
      }
      
      return false;
    }
  }
  
  // Generate thumbnail for video files
  Future<String?> _generateThumbnail() async {
    // Usa sempre il PRIMO media (video) per generare la thumbnail
    final bool primaryIsImage = _isImageFiles.isNotEmpty ? _isImageFiles.first : widget.isImageFile;
    if (primaryIsImage) return null;
    final File primaryFile = _mediaFiles.isNotEmpty ? _mediaFiles.first : widget.mediaFile;
    
    try {
      print('Generating thumbnail for: ${primaryFile.path}');
      
      // Use video_thumbnail package to generate thumbnail
      final thumbnailBytes = await VideoThumbnail.thumbnailData(
        video: primaryFile.path,
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
      final thumbnailFile = await _saveThumbnailToFile(thumbnailBytes);
      if (thumbnailFile != null) {
        print('Thumbnail generated and saved at: ${thumbnailFile.path}');
        _thumbnailPath = thumbnailFile.path;
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
  Future<File?> _saveThumbnailToFile(Uint8List thumbnailBytes) async {
    try {
      final fileName = widget.mediaFile.path.split('/').last;
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
  
  // Upload to Facebook using the Cloudflare URL for a specific account
  Future<void> _uploadToFacebook({
    required Map<String, dynamic> account,
    required String description
  }) async {
    final String accountId = account['id'];
    
    // Debug: entrypoint log to ensure we see logs during Facebook flow
    print('>>> [FACEBOOK] Starting upload flow for account: ' + accountId + ' (isImage: ' + widget.isImageFile.toString() + ')');

    setState(() {
      _accountStatus[accountId] = 'Preparing upload to Facebook...';
      _accountProgress[accountId] = 0.6; // 60%
    });
    
    try {
      // Get Facebook account data
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Utente non autenticato');
      }
      
      // Get account data from Firebase
      DatabaseReference baseRef = FirebaseDatabase.instance.ref();
      DataSnapshot accountSnapshot = await baseRef
          .child('users')
          .child(currentUser.uid)
          .child('facebook')
          .child(accountId)
          .get();
      // Fallback paths if the first is missing (some environments use users/users/...)
      if (!accountSnapshot.exists) {
        print('>>> [FACEBOOK] Primary FB account path not found, trying fallback path users/users/...');
        accountSnapshot = await baseRef
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('facebook')
            .child(accountId)
            .get();
      }
      if (!accountSnapshot.exists) {
        print('>>> [FACEBOOK] Second FB account path not found, trying social_accounts path users/users/.../social_accounts/facebook');
        accountSnapshot = await baseRef
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('social_accounts')
            .child('facebook')
            .child(accountId)
            .get();
      }
      
      if (!accountSnapshot.exists) {
        throw Exception('Account Facebook non trovato');
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      // Prefer page_access_token, then access_token/page_token/token
      final accessToken = (accountData['page_access_token'] ?? accountData['access_token'] ?? accountData['page_token'] ?? accountData['token']);
      // Prefer explicit page_id, else fallback to stored id, else last resort selection id
      final pageId = accountData['page_id'] ?? accountData['id'] ?? accountId;
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Token di accesso Facebook non trovato');
      }
      
      print('>>> [FACEBOOK] Loaded FB account data - pageId: ' + pageId.toString());

      // Determine media type (video or image)
      final bool isImage = widget.isImageFile;
      
      setState(() {
        _accountStatus[accountId] = 'Initializing upload session to Facebook...';
        _accountProgress[accountId] = 0.65; // 65%
      });
      
      if (isImage) {
        // Per le immagini possiamo utilizzare il metodo di upload tramite URL
        if (_cloudflareUrl == null) {
          throw Exception('URL dell\'immagine non disponibile');
        }
        
        // Verifica l'accessibilità dell'URL
        bool isAccessible = await _verifyFileAccessibility(_cloudflareUrl!);
        
        if (!isAccessible) {
          print('ATTENZIONE: URL dell\'immagine non accessibile pubblicamente: $_cloudflareUrl');
          throw Exception('URL dell\'immagine non accessibile pubblicamente. Facebook richiede URL accessibili.');
        }
        
        setState(() {
          _accountStatus[accountId] = 'Pubblicazione immagine su Facebook...';
          _accountProgress[accountId] = 0.9; // 90%
        });
        
        // Publish image directly via URL
        final publishParams = {
          'access_token': accessToken,
          'url': _cloudflareUrl!,
          'caption': description,
        };
        
        final publishResponse = await http.post(
          Uri.parse('https://graph.facebook.com/${_facebookApiVersion}/$pageId/photos'),
          body: publishParams,
        );
        
        if (publishResponse.statusCode != 200) {
          throw Exception('Errore nella pubblicazione dell\'immagine su Facebook: ${publishResponse.body}');
        }
        
        // Parse the response to get the post_id
        final publishData = json.decode(publishResponse.body);
        final postId = publishData['id'];
        
        // Save the post_id for this account
        if (postId != null) {
          _accountPostIds[accountId] = postId.toString();
          print('Facebook post_id saved for account $accountId: $postId');
        }
      } else {
        // Pre-validate video specs for Reels requirements (see docs/facebook/faceupload.md)
        int? videoSeconds;
        int? videoWidth;
        int? videoHeight;
        try {
          final VideoPlayerController controller = VideoPlayerController.file(widget.mediaFile);
          await controller.initialize();
          final Duration duration = controller.value.duration;
          final Size size = controller.value.size;
          videoSeconds = duration.inSeconds;
          videoWidth = size.width.round();
          videoHeight = size.height.round();
          await controller.dispose();
        } catch (_) {}
        bool meetsDuration = videoSeconds != null && videoSeconds >= 3 && videoSeconds <= 90;
        bool meetsResolution = videoWidth != null && videoHeight != null &&
            ((videoWidth >= 540 && videoHeight >= 960) || (videoWidth >= 960 && videoHeight >= 540));
        bool isPortrait = videoWidth != null && videoHeight != null && videoHeight > videoWidth;
        bool meetsAspect = false;
        if (videoWidth != null && videoHeight != null && videoHeight != 0) {
          final double ratio = videoWidth / videoHeight;
          const double target = 9.0 / 16.0;
          meetsAspect = (ratio - target).abs() <= 0.03; // tolleranza 3%
        }
        final bool eligibleForReels = meetsDuration && meetsResolution && isPortrait && meetsAspect;

        if (!eligibleForReels) {
          if (!mounted) return;
          setState(() {
            _accountStatus[accountId] = 'Publishing standard Facebook video...';
            _accountProgress[accountId] = 0.75;
          });
          // Publish as standard Page video using file_url
          if (_cloudflareUrl == null) {
            throw Exception('URL del video non disponibile');
          }
          final altPublish = await http.post(
            Uri.parse('https://graph.facebook.com/${_facebookApiVersion}/$pageId/videos'),
            body: {
              'access_token': accessToken,
              'file_url': _cloudflareUrl!,
              'description': description,
              'published': 'true',
            },
          );
          if (altPublish.statusCode != 200) {
            throw Exception('Errore pubblicazione video standard: ${altPublish.body}');
          }
          final altData = json.decode(altPublish.body);
          final newVideoId = (altData is Map) ? (altData['id']?.toString()) : null;
          if (newVideoId == null || newVideoId.isEmpty) {
            throw Exception('Risposta pubblicazione video standard non valida: ${altPublish.body}');
          }
          _accountPostIds[accountId] = newVideoId;
          if (!mounted) return;
          setState(() {
            _accountProgress[accountId] = 1.0;
            _accountStatus[accountId] = 'Uploaded successfully to Facebook!';
            _accountComplete[accountId] = true;
            _accountError[accountId] = null;
            _completedPlatforms.add('Facebook');
          });
          return;
        }

        // Per i video, dobbiamo utilizzare il metodo di upload diretto in chunk
        // Segui la documentazione per Resumable Upload API
        
        // Step 1: Initialize upload session
        final fileName = path.basename(widget.mediaFile.path);
        final fileSize = await widget.mediaFile.length();
        
        final initParams = {
          'access_token': accessToken,
          'upload_phase': 'start',
        };
        
        final initResponse = await http.post(
          Uri.parse('https://graph.facebook.com/${_facebookApiVersion}/$pageId/video_reels'),
          body: initParams,
        );
        
        if (initResponse.statusCode != 200) {
          throw Exception('Errore nell\'inizializzazione dell\'upload video Facebook: ${initResponse.body}');
        }
        // Check for error field even on 200
        try {
          final initCheck = json.decode(initResponse.body);
          if (initCheck is Map && initCheck.containsKey('error')) {
            throw Exception('Errore API Facebook (init): ' + initResponse.body);
          }
        } catch (_) {}
        
        final initData = json.decode(initResponse.body);
        final videoId = initData['video_id'];
        final uploadUrl = initData['upload_url'];
        
        if (videoId == null || uploadUrl == null) {
          throw Exception('ID video o URL di upload non validi nella risposta Facebook');
        }
        
        print('>>> [FACEBOOK] Upload session initialized. videoId: ' + videoId.toString() + ' uploadUrl: ' + uploadUrl.toString());

        setState(() {
          _accountStatus[accountId] = 'Uploading video to Facebook...';
          _accountProgress[accountId] = 0.7; // 70%
        });
        
        // Step 2: Upload the file (prefer hosted URL if available)
        bool uploadOk = false;
        try {
          if (_cloudflareUrl != null && _cloudflareUrl!.isNotEmpty) {
            print('>>> [FACEBOOK] Using hosted upload via file_url');
            final hostedReq = http.Request('POST', Uri.parse(uploadUrl));
            hostedReq.headers['Authorization'] = 'OAuth $accessToken';
            hostedReq.headers['file_url'] = _cloudflareUrl!;
            // Some implementations also require file_size, include for safety
            hostedReq.headers['file_size'] = fileSize.toString();
            // Optional: hint content type to backend
            hostedReq.headers['Content-Type'] = 'application/octet-stream';
            final hostedResp = await hostedReq.send();
            final hostedBody = await hostedResp.stream.bytesToString();
            print('>>> [FACEBOOK] Hosted upload response: ' + hostedBody);
            if (hostedResp.statusCode == 200) {
              final parsed = json.decode(hostedBody);
              uploadOk = parsed is Map && parsed['success'] == true;
            }
          }
        } catch (e) {
          print('>>> [FACEBOOK] Hosted upload failed, will fallback to direct bytes. Err: ' + e.toString());
        }

        if (!uploadOk) {
          print('>>> [FACEBOOK] Fallback: uploading raw bytes to rupload');
          final fileBytes = await widget.mediaFile.readAsBytes();
          final uploadRequest = http.Request('POST', Uri.parse(uploadUrl));
          uploadRequest.headers['Authorization'] = 'OAuth $accessToken';
          uploadRequest.headers['offset'] = '0';
          uploadRequest.headers['file_size'] = fileSize.toString();
          uploadRequest.headers['Content-Type'] = 'application/octet-stream';
          uploadRequest.bodyBytes = fileBytes;
          final uploadResponse = await uploadRequest.send();
          final uploadResponseStr = await uploadResponse.stream.bytesToString();
          print('>>> [FACEBOOK] Byte upload response: ' + uploadResponseStr);
          if (uploadResponse.statusCode != 200) {
            throw Exception('Errore nel caricamento del video su Facebook: ' + uploadResponseStr);
          }
          final uploadData = json.decode(uploadResponseStr);
          if (uploadData is Map && uploadData.containsKey('error')) {
            throw Exception('Errore nel caricamento del video (API error): ' + uploadResponseStr);
          }
          if (uploadData['success'] != true) {
            throw Exception('Errore nel caricamento del video su Facebook: ' + uploadResponseStr);
          }
        }
        
        // Check video processing status
        bool isVideoReady = false;
        int statusChecks = 0;
        const maxStatusChecks = 10;
        
        if (!mounted) return;
        setState(() {
          _accountStatus[accountId] = 'Video processing on Facebook...';
          _accountProgress[accountId] = 0.8; // 80%
        });
        
        while (!isVideoReady && statusChecks < maxStatusChecks) {
          statusChecks++;
          
          final statusResponse = await http.get(
            Uri.parse('https://graph.facebook.com/${_facebookApiVersion}/$videoId')
              .replace(queryParameters: {
                'fields': 'status',
                'access_token': accessToken,
              }),
          );
          
          if (statusResponse.statusCode == 200) {
            final statusData = json.decode(statusResponse.body);
            final status = statusData['status'];
            
            print('Status video Facebook: $status');
            
            if (status != null && status['video_status'] == 'ready') {
              isVideoReady = true;
              break;
            } else if (status != null && status['processing_phase'] != null && 
                      status['processing_phase']['status'] == 'error') {
              final dynamic procError = status['processing_phase']['error'];
              final String errMsg = (procError != null && procError is Map && procError['message'] != null)
                  ? procError['message'].toString()
                  : 'Errore sconosciuto in fase di elaborazione';
              throw Exception('Errore nell\'elaborazione del video: ' + errMsg);
            }
          }
          
          if (!mounted) return;
          setState(() {
            _accountStatus[accountId] = 'Video processing on Facebook (${statusChecks}/$maxStatusChecks)...';
            _accountProgress[accountId] = 0.8 + (statusChecks / maxStatusChecks * 0.1); // 80-90%
          });
          
          await Future.delayed(Duration(seconds: 3));
        }
        
        if (!mounted) return;
        setState(() {
          _accountStatus[accountId] = 'Publishing video to Facebook...';
          _accountProgress[accountId] = 0.9; // 90%
        });
        
        // Step 3: Finish the upload and publish
        final publishParams = {
          'access_token': accessToken,
          'video_id': videoId,
          'upload_phase': 'finish',
          'video_state': 'PUBLISHED',
          'description': description,
        };
        
        if (widget.platformDescriptions.containsKey('Facebook') &&
            widget.platformDescriptions['Facebook']!.containsKey('${accountId}_title') &&
            widget.platformDescriptions['Facebook']!['${accountId}_title']!.isNotEmpty) {
          publishParams['title'] = widget.platformDescriptions['Facebook']!['${accountId}_title']!;
        } else if (widget.title.isNotEmpty) {
          publishParams['title'] = widget.title;
        }
        
        final publishResponse = await http.post(
          Uri.parse('https://graph.facebook.com/${_facebookApiVersion}/$pageId/video_reels'),
          body: publishParams,
        );
        
        print('>>> [FACEBOOK] Publish response: ' + publishResponse.body);
        
        if (publishResponse.statusCode != 200) {
          throw Exception('Errore nella pubblicazione del video su Facebook: ${publishResponse.body}');
        }
        
        final publishData = json.decode(publishResponse.body);
        if (publishData is Map && publishData.containsKey('error')) {
          throw Exception('Errore nella pubblicazione del video (API error): ${publishResponse.body}');
        }
        if (publishData['success'] != true) {
          throw Exception('Errore nella pubblicazione del video su Facebook: ${publishResponse.body}');
        }

        // Verify publishing phase completes before reporting success
        if (!mounted) return;
        setState(() {
          _accountStatus[accountId] = 'Finalizing publication on Facebook...';
          _accountProgress[accountId] = 0.92;
        });
        bool published = false;
        int publishChecks = 0;
        const maxPublishChecks = 30;
        bool processingError = false;
        while (!published && publishChecks < maxPublishChecks && !processingError) {
          publishChecks++;
          final statusResponse = await http.get(
            Uri.parse('https://graph.facebook.com/${_facebookApiVersion}/$videoId')
              .replace(queryParameters: {
                'fields': 'status',
                'access_token': accessToken,
              }),
          );
          if (statusResponse.statusCode == 200) {
            final statusData = json.decode(statusResponse.body);
            final status = statusData['status'];
            if (status != null) {
              final pubPhase = (status['publishing_phase'] != null) ? status['publishing_phase']['status'] : null;
              final vStatus = status['video_status'];
              if ((pubPhase == 'complete') || (vStatus == 'ready' || vStatus == 'published')) {
                published = true;
                break;
              }
              if (status['processing_phase'] != null && status['processing_phase']['status'] == 'error') {
                processingError = true;
              }
            }
          }
          if (!mounted) return;
          setState(() {
            _accountStatus[accountId] = 'Publishing on Facebook (${publishChecks}/$maxPublishChecks)...';
            _accountProgress[accountId] = 0.92 + (publishChecks / maxPublishChecks * 0.06);
          });
          await Future.delayed(Duration(seconds: 3));
        }
        // If Reels publish does not show completion, try fallback to /{page_id}/videos endpoint
        if (!published) {
          if (!mounted) return;
          setState(() {
            _accountStatus[accountId] = 'Fallback publish on Facebook videos...';
            _accountProgress[accountId] = 0.96;
          });
          // Try publishing as a standard Page video with file_url
          http.Response? altPublish;
          try {
            altPublish = await http.post(
              Uri.parse('https://graph.facebook.com/${_facebookApiVersion}/$pageId/videos'),
              body: {
                'access_token': accessToken,
                'file_url': _cloudflareUrl ?? '',
                'description': description,
                'published': 'true',
              },
            );
            if (altPublish.statusCode == 200) {
              final altData = json.decode(altPublish.body);
              if (altData is Map && (altData['id'] != null || altData['success'] == true)) {
                published = true;
              }
            }
          } catch (_) {}
          // As secondary fallback, attempt /videos with the rupload video_id
          if (!published) {
            try {
              final altPublish2 = await http.post(
                Uri.parse('https://graph.facebook.com/${_facebookApiVersion}/$pageId/videos'),
                body: {
                  'access_token': accessToken,
                  'video_id': videoId,
                  'description': description,
                  'published': 'true',
                },
              );
              if (altPublish2.statusCode == 200) {
                final altData2 = json.decode(altPublish2.body);
                if (altData2 is Map && (altData2['id'] != null || altData2['success'] == true)) {
                  published = true;
                }
              }
            } catch (_) {}
          }
          if (!published) {
            throw Exception('Pubblicazione non completata su Facebook dopo fallback a /videos');
          }
        }
        
        // Save the post_id (video_id) for this account
        if (videoId != null) {
          _accountPostIds[accountId] = videoId.toString();
          print('Facebook post_id saved for account $accountId: $videoId');
        }
      }
      
      // Success!
      if (!mounted) return;
      setState(() {
        _accountProgress[accountId] = 1.0; // 100%
        _accountStatus[accountId] = 'Uploaded successfully to Facebook!';
        _accountComplete[accountId] = true;
        _accountError[accountId] = null;
        _completedPlatforms.add('Facebook');
      });
      
    } catch (e) {
      print('Facebook upload error: $e');
      
      // Handle retry if needed
      _facebookUploadAttempts[accountId] = (_facebookUploadAttempts[accountId] ?? 0) + 1;
      
      if (_facebookUploadAttempts[accountId]! < _maxFacebookAttempts) {
        print('Retrying Facebook upload (attempt ${_facebookUploadAttempts[accountId]} of $_maxFacebookAttempts)');
        
        if (!mounted) return;
        setState(() {
      _accountStatus[accountId] = 'Retry attempt ${_facebookUploadAttempts[accountId]} of $_maxFacebookAttempts...';
          _accountProgress[accountId] = 0.5; // Reset progress for retry
        });
        
        // Wait before retrying
        await Future.delayed(Duration(seconds: 2));
        return _uploadToFacebook(account: account, description: description);
      }
      
      if (!mounted) return;
      setState(() {
        String errorMsg = e.toString();
        if (errorMsg.contains('accessibilità') || errorMsg.contains('accessible')) {
          errorMsg =
              'Facebook could not access the video URL. Please check your internet connection, then try the upload again.';
        } else if (errorMsg.contains('token')) {
          errorMsg =
              'Facebook authentication error. Please reconnect this Facebook page from the Social Accounts page, then try again.';
        } else if (errorMsg.contains('fetch video file')) {
          errorMsg =
              'Facebook could not fetch this video file. Check that the video format and size are supported, then try again.';
        }
        
        _accountError[accountId] = errorMsg;
        _accountComplete[accountId] = true; // Mark as complete with error
        _accountProgress[accountId] = 1.0; // 100% (with error)
        _completedPlatforms.add('Facebook');
      });
    }
  }
  
  // Build platform containers for all selected accounts
  Widget _buildPlatformContainers({bool isDark = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_instagramAccounts.isNotEmpty)
          _buildPlatformSection('Instagram', _instagramAccounts, isDark: isDark),
        if (_youtubeAccounts.isNotEmpty)
          _buildPlatformSection('YouTube', _youtubeAccounts, isDark: isDark),
        if (_twitterAccounts.isNotEmpty)
          _buildPlatformSection('Twitter', _twitterAccounts, isDark: isDark),
        if (_threadsAccounts.isNotEmpty)
          _buildPlatformSection('Threads', _threadsAccounts, isDark: isDark),
        if (_facebookAccounts.isNotEmpty)
          _buildPlatformSection('Facebook', _facebookAccounts, isDark: isDark),
        if (_tiktokAccounts.isNotEmpty)
          _buildPlatformSection('TikTok', _tiktokAccounts, isDark: isDark),
      ],
    );
  }
  
  // Build a section for a specific platform with its accounts
  Widget _buildPlatformSection(String platform, List<Map<String, dynamic>> accounts, {bool isDark = false}) {
    String logoPath = 'assets/loghi/logo_insta.png'; // Default
    switch (platform) {
      case 'Instagram':
        logoPath = 'assets/loghi/logo_insta.png';
        break;
      case 'YouTube':
        logoPath = 'assets/loghi/logo_yt.png';
        break;
      case 'Twitter':
        logoPath = 'assets/loghi/logo_twitter.png';
        break;
      case 'Threads':
        logoPath = 'assets/loghi/threads_logo.png';
        break;
      case 'Facebook':
        logoPath = 'assets/loghi/logo_facebook.png';
        break;
      case 'TikTok':
        logoPath = 'assets/loghi/logo_tiktok.png';
        break;
    }
    final platformTextColor = isDark ? Colors.white : Color(0xFF2C2C3E);
    final containerColor = isDark ? Colors.grey[850] : Colors.white;
    final borderColor = isDark ? Colors.grey[700]! : _platformColors[platform]!.withOpacity(0.1);
    final boxShadowColor = isDark ? Colors.black.withOpacity(0.25) : _platformColors[platform]!.withOpacity(0.15);
    return Container(
      margin: EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Platform header with logo
          Row(
            children: [
              // Platform logo
              Container(
                width: 32,
                height: 32,
                margin: EdgeInsets.only(right: 12),
                child: Image.asset(
                  logoPath,
                  fit: BoxFit.contain,
                ),
              ),
              // Platform name
              Text(
                '$platform Accounts',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: platformTextColor,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          // Platform accounts container
          Container(
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: boxShadowColor,
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: borderColor,
                width: 1,
              ),
            ),
            child: Column(
              children: accounts.map((account) => 
                _buildAccountContainer(platform, account)
              ).toList(),
            ),
          ),
        ],
      ),
    );
  }
  
  // Build a single account container with improved minimal design
  Widget _buildAccountContainer(String platform, Map<String, dynamic> account) {
    final accountId = account['id'] as String;
    String username;
    if (platform == 'TikTok') {
      username = (account['display_name'] != null && account['display_name'].toString().isNotEmpty)
        ? account['display_name']
        : (account['username'] ?? 'Account $accountId');
    } else {
      username = account['username'] ?? 'Account $accountId';
    }
    final progress = _accountProgress[accountId] ?? 0.0;
    final status = _accountStatus[accountId] ?? 'Pending...';
    final isComplete = _accountComplete[accountId] ?? false;
    final error = _accountError[accountId];
    final profileImage = _profileImages[accountId];
    final platformColor = _platformColors[platform] ?? Colors.grey;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // First/Last entry detection for proper rounded corners
    final bool isFirstAccount = true; // We handle this in the container UI now
    final bool isLastAccount = true;  // We handle this in the container UI now
    return Container(
      decoration: BoxDecoration(
        border: !isLastAccount ? Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey.withOpacity(0.1),
            width: 1,
          ),
        ) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Profile image
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: platformColor.withOpacity(isDark ? 0.18 : 0.1),
                border: Border.all(
                  color: platformColor.withOpacity(isDark ? 0.28 : 0.2),
                  width: 1,
                ),
              ),
              child: ClipOval(
                child: profileImage != null && profileImage.isNotEmpty
                    ? FadeInImage.assetNetwork(
                        placeholder: 'assets/loghi/logo_${platform.toLowerCase()}.png',
                        image: profileImage,
                        fit: BoxFit.cover,
                        imageErrorBuilder: (context, error, stackTrace) {
                          return Icon(
                            _getPlatformIcon(platform),
                            color: platformColor,
                            size: 20,
                          );
                        },
                      )
                    : Image.asset(
                        'assets/loghi/logo_${platform.toLowerCase()}.png',
                        fit: BoxFit.contain,
                        width: 22,
                        height: 22,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            _getPlatformIcon(platform),
                            color: platformColor,
                            size: 20,
                          );
                        },
                      ),
              ),
            ),
            SizedBox(width: 14),
            // Account info and progress
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Username and status badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          platform == 'YouTube' ? username : '@$username',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isDark ? Colors.white : Color(0xFF2C2C3E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Status badge
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isComplete
                              ? (isDark ? Colors.green[700]!.withOpacity(0.18) : Colors.green.withOpacity(0.15))
                              : (isDark ? platformColor.withOpacity(0.18) : platformColor.withOpacity(0.15)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isComplete ? 'Completed' : 'Ready',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isComplete
                                ? (isDark ? Colors.green[200] : Colors.green)
                                : (isDark ? platformColor.withOpacity(0.85) : platformColor),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  // Status message
                  Text(
                    error != null
                        ? error
                        : (isComplete
                            ? (isDark ? 'Upload completed' : 'Upload completed')
                            : status),
                    style: TextStyle(
                      color: error != null
                          ? Colors.red[400]
                          : (isComplete
                              ? (isDark ? Colors.green[200] : Colors.green[700])
                              : (isDark ? Colors.grey[300] : Colors.grey[700])),
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Get icon for platform
  IconData _getPlatformIcon(String platform) {
    switch (platform) {
      case 'Instagram': return Icons.camera_alt;
      case 'YouTube': return Icons.play_arrow;
      case 'Twitter': return Icons.chat;
      case 'Threads': return Icons.tag;
      case 'Facebook': return Icons.facebook;
      case 'TikTok': return Icons.music_note;
      default: return Icons.public;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appBlueColor = const Color(0xFF64B5F6);
    
    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      appBar: null,
      body: SafeArea(
        child: Column(
          children: [
            // Header from about_page.dart
            _buildHeader(context),
            
            // Main content
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : const Color(0xFFF8F8F8),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Upload containers (scrollable)
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Circular Upload Status moved to top
                            Center(child: _buildCircularUploadStatus(theme)),
                            SizedBox(height: 8),
                            SizedBox(height: 24),
                            
                            // Title and description removed as requested
                            
                            // Build platform containers
                            _buildPlatformContainers(isDark: isDark),
                            
                            SizedBox(height: 16),
                            
                            // Error message
                            if (_errorMessage != null && !_isUploading)
                              Container(
                                padding: EdgeInsets.all(16),
                                margin: EdgeInsets.only(bottom: 20),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // Success message removed
                          ],
                        ),
                      ),
                    ),
                    // Collapsible tips section
                    _buildCollapsibleTips(appBlueColor),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _isUploading ? null : SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                stops: [0.0, 1.0],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton(
              onPressed: () {
                // Naviga alla home page e pulisci tutto lo stack di navigazione
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/',
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                'Completed', // Solo testo, senza ✓
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Build header like in about_page.dart
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
                    onPressed: _isUploading ? null : () => Navigator.pop(context),
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
                      'Upload',
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

  // Build collapsible tips carousel widget with animation
  Widget _buildCollapsibleTips(Color appBlueColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Material(
      color: isDark ? Colors.grey[850] : Colors.white,
      elevation: 4,
      shadowColor: Colors.black.withOpacity(isDark ? 0.18 : 0.1),
      child: InkWell(
        onTap: _toggleTipsVisibility,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tips header always visible
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  // App logo using actual app icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: appBlueColor.withOpacity(0.3),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/onboarding/circleICON.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback if asset not found
                          return CircleAvatar(
                            backgroundColor: appBlueColor,
                            radius: 16,
                            child: Text(
                              'V',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Fluzar Tips',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF2C2C3E),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Spacer(),
                  // Next tip button
                  if (_isTipsExpanded)
                    InkWell(
                      onTap: _nextTip,
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: appBlueColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.navigate_next,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  SizedBox(width: 8),
                  // Expand/collapse button with animation
                  AnimatedRotation(
                    turns: _isTipsExpanded ? 0.5 : 0.0,
                    duration: Duration(milliseconds: 300),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            // Tip content with animation
            AnimatedContainer(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _isTipsExpanded ? null : 0,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(),
              child: AnimatedOpacity(
                opacity: _isTipsExpanded ? 1.0 : 0.0,
                duration: Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: 500),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: Offset(0.1, 0.0),
                            end: Offset(0.0, 0.0),
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Row(
                      key: ValueKey<int>(_currentTipIndex),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: EdgeInsets.only(top: 4),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _getTipColor(_currentTipIndex),
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            viralTips[_currentTipIndex],
                            style: TextStyle(
                              color: isDark ? Colors.grey[100] : const Color(0xFF2C2C3E),
                              fontSize: 15,
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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
  
  // Return different colors for different tips to add visual variety
  Color _getTipColor(int index) {
    final colors = [
      const Color(0xFFC974E8), // Purple
      const Color(0xFFF7C167), // Orange
      const Color(0xFF67E4C8), // Teal
    ];
    
    return colors[index % colors.length];
  }

  // Generate segments for circular progress indicator
  List<ProgressSegment> _generateProgressSegments() {
    List<ProgressSegment> segments = [];
    
    // If no accounts selected, show empty circle
    if (_totalSelectedAccounts == 0) {
      return segments;
    }

    // For a more natural progression, we'll distribute the segments more evenly
    // Cloudflare upload will occupy 30% of the circle
    // Individual platform uploads will occupy 70% of the circle together
    double cloudflareSegmentSize = 30.0;
    double platformsSegmentSize = 70.0;
    
    // Calculate cloudflare percentage based on progress
    double cloudflarePercentage = 0;
    if (_uploadProgress < 0.5) {
      // Normalize the progress from 0-0.5 to 0-100% for Cloudflare segment
      cloudflarePercentage = (_uploadProgress / 0.5) * cloudflareSegmentSize;
    } else {
      cloudflarePercentage = cloudflareSegmentSize; // Complete segment
    }
    
          // Add File structuring segment first
      segments.add(
        ProgressSegment(
          name: 'File structuring',
          percentage: cloudflarePercentage,
          color: _platformColors['file_structuring']!,
        )
      );
    
    // Calculate how much space each platform should take
    double platformSegmentSize = platformsSegmentSize / _totalSelectedAccounts;
    
    // Function to calculate individual platform progress
    double calculatePlatformSegment(double progress) {
      if (progress <= 0.5) return 0; // Not started yet
      
      // Normalize the progress from 0.5-1.0 to 0-100% for platform segment
      return ((progress - 0.5) / 0.5) * platformSegmentSize;
    }
    
    // Add segments for Instagram accounts
    for (var account in _instagramAccounts) {
                  final accountId = account['id'] as String;
                  final progress = _accountProgress[accountId] ?? 0.0;
      final platformProgress = calculatePlatformSegment(progress);
      
      // Always add segment for consistent appearance, but with 0 size if not started
      segments.add(
        ProgressSegment(
          name: 'Instagram: ${account['username']}',
          percentage: platformProgress,
          color: _platformColors['Instagram']!,
        )
      );
    }
    
    // Add segments for YouTube accounts
    for (var account in _youtubeAccounts) {
      final accountId = account['id'] as String;
      final progress = _accountProgress[accountId] ?? 0.0;
      final platformProgress = calculatePlatformSegment(progress);
      
      segments.add(
        ProgressSegment(
          name: 'YouTube: ${account['username']}',
          percentage: platformProgress,
          color: _platformColors['YouTube']!,
        )
      );
    }
    
    // Add segments for Twitter accounts
    for (var account in _twitterAccounts) {
      final accountId = account['id'] as String;
      final progress = _accountProgress[accountId] ?? 0.0;
      final platformProgress = calculatePlatformSegment(progress);
      
      segments.add(
        ProgressSegment(
          name: 'Twitter: ${account['username']}',
          percentage: platformProgress,
          color: _platformColors['Twitter']!,
        )
      );
    }
    
    // Add segments for Threads accounts
    for (var account in _threadsAccounts) {
      final accountId = account['id'] as String;
      final progress = _accountProgress[accountId] ?? 0.0;
      final platformProgress = calculatePlatformSegment(progress);
      
      segments.add(
        ProgressSegment(
          name: 'Threads: ${account['username']}',
          percentage: platformProgress,
          color: _platformColors['Threads']!,
        )
      );
    }
    
    // Add segments for Facebook accounts
    for (var account in _facebookAccounts) {
      final accountId = account['id'] as String;
      final progress = _accountProgress[accountId] ?? 0.0;
      final platformProgress = calculatePlatformSegment(progress);
      
      segments.add(
        ProgressSegment(
          name: 'Facebook: ${account['username']}',
          percentage: platformProgress,
          color: _platformColors['Facebook']!,
        )
      );
    }
    
    // Add segments for TikTok accounts
    for (var account in _tiktokAccounts) {
      final accountId = account['id'] as String;
      final progress = _accountProgress[accountId] ?? 0.0;
      final platformProgress = calculatePlatformSegment(progress);
      
      segments.add(
        ProgressSegment(
          name: 'TikTok: ${account['username']}',
          percentage: platformProgress,
          color: _platformColors['TikTok']!,
        )
      );
    }
    
    return segments;
  }

  // Build circular upload status indicator
  Widget _buildCircularUploadStatus(ThemeData theme) {
    final segments = _generateProgressSegments();
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: EdgeInsets.only(top: 10, bottom: 25),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Circular progress indicator
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF6C63FF).withOpacity(0.2),
                  blurRadius: 15,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background circle
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.grey[850] : Colors.grey[100],
                  ),
                ),
                // Custom circular progress indicator with gradient effect
                ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      colors: [
                                        Color(0xFF6C63FF), // Fluzar primary color
                Color(0xFFFF6B6B), // Fluzar secondary color
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds);
                  },
                  child: CustomPaint(
                    size: Size(220, 220),
                    painter: CircularProgressPainter(
                      segments: segments,
                      strokeWidth: 22,
                      smoothTransition: true,
                      gap: 0.04,
                    ),
                  ),
                ),
                // Center
                Container(
                  width: 165,
                  height: 165,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.grey[900] : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return LinearGradient(
                              colors: [
                                Color(0xFF6C63FF),
                                Color(0xFFFF6B6B),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds);
                          },
                          child: Text(
                            '${(_uploadProgress * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          _isUploading ? 'In progress...' : (_uploadComplete ? 'Completed' : 'Waiting...'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.grey[300] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Status message
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey[100] : Colors.grey[800],
              ),
            ),
          ),
          // Platform legend if needed
          if (segments.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: segments.map((segment) => _buildLegendItem(segment, isDark: isDark)).toList(),
              ),
            ),
        ],
      ),
    );
  }
  
  // Build legend item for each platform
  Widget _buildLegendItem(ProgressSegment segment, {bool isDark = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: segment.name.contains('file_structuring') 
          ? LinearGradient(
              colors: [
                Color(0xFF6C63FF),
                Color(0xFFFF6B6B),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
        color: segment.name.contains('file_structuring') ? null : segment.color.withOpacity(isDark ? 0.28 : 0.2),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: segment.name.contains('file_structuring') ? Colors.white : segment.color,
            ),
          ),
          SizedBox(width: 6),
          Text(
            segment.name.split(':').first,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: segment.name.contains('file_structuring') 
                ? Colors.white 
                : (isDark ? Colors.white : segment.color.withOpacity(0.9)),
            ),
          ),
        ],
      ),
    );
  }

  // Load profile images for accounts
  Future<void> _loadProfileImages() async {
    try {
      print('Starting to load profile images...');
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('No current user found for profile image loading');
        return;
      }
      
      // Load Instagram profile images
      for (var account in _instagramAccounts) {
        final accountId = account['id'] as String;
        final username = account['username'] ?? 'unknown';
        print('Loading Instagram profile image for $username (ID: $accountId)');
        
        try {
          // Check in users/[uid]/instagram/[accountId]
          final snapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child(currentUser.uid)
              .child('instagram')
              .child(accountId)
              .child('profile_image_url')
              .get();
          
          if (snapshot.exists && snapshot.value != null) {
            final profileUrl = snapshot.value as String;
            print('Found Instagram profile image: $profileUrl');
            setState(() {
              _profileImages[accountId] = profileUrl;
            });
            continue; // Skip other checks if found
          }
          
          // Check in users/users/[uid]/instagram/[accountId]
          final altSnapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child('users')
              .child(currentUser.uid)
              .child('instagram')
              .child(accountId)
              .child('profile_image_url')
              .get();
          
          if (altSnapshot.exists && altSnapshot.value != null) {
            final profileUrl = altSnapshot.value as String;
            print('Found Instagram profile image (alt path): $profileUrl');
            setState(() {
              _profileImages[accountId] = profileUrl;
            });
            continue; // Skip other checks if found
          }
          
          // Check in users/users/[uid]/social_accounts/instagram/[accountId]
          final socialSnapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child('users')
              .child(currentUser.uid)
              .child('social_accounts')
              .child('instagram')
              .child(accountId)
              .child('profile_image_url')
              .get();
          
          if (socialSnapshot.exists && socialSnapshot.value != null) {
            final profileUrl = socialSnapshot.value as String;
            print('Found Instagram profile image (social_accounts path): $profileUrl');
            setState(() {
              _profileImages[accountId] = profileUrl;
            });
          } else {
            print('No profile image found for Instagram account: $username');
          }
        } catch (e) {
          print('Error loading Instagram profile for $username: $e');
        }
      }
      
      // Load YouTube profile images
      for (var account in _youtubeAccounts) {
        final accountId = account['id'] as String;
        final username = account['username'] ?? 'unknown';
        print('Loading YouTube profile image for $username (ID: $accountId)');
        
        try {
          // Check in users/[uid]/youtube/[accountId]
          final snapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child(currentUser.uid)
              .child('youtube')
              .child(accountId)
              .child('thumbnail_url')
              .get();
          
          if (snapshot.exists && snapshot.value != null) {
            final profileUrl = snapshot.value as String;
            print('Found YouTube profile image: $profileUrl');
            setState(() {
              _profileImages[accountId] = profileUrl;
            });
            continue; // Skip other checks if found
          }
          
          // Check in users/users/[uid]/youtube/[accountId]
          final altSnapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child('users')
              .child(currentUser.uid)
              .child('youtube')
              .child(accountId)
              .child('thumbnail_url')
              .get();
          
          if (altSnapshot.exists && altSnapshot.value != null) {
            final profileUrl = altSnapshot.value as String;
            print('Found YouTube profile image (alt path): $profileUrl');
            setState(() {
              _profileImages[accountId] = profileUrl;
            });
          } else {
            print('No profile image found for YouTube account: $username');
          }
        } catch (e) {
          print('Error loading YouTube profile for $username: $e');
        }
      }
      
      // Load Twitter profile images
      for (var account in _twitterAccounts) {
        final accountId = account['id'] as String;
        final username = account['username'] ?? 'unknown';
        print('Loading Twitter profile image for $username (ID: $accountId)');
        
        try {
          // Check in users/users/[uid]/social_accounts/twitter/[accountId]
          final snapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child('users')
              .child(currentUser.uid)
              .child('social_accounts')
              .child('twitter')
              .child(accountId)
              .child('profile_image_url')
              .get();
          
          if (snapshot.exists && snapshot.value != null) {
            final profileUrl = snapshot.value as String;
            print('Found Twitter profile image: $profileUrl');
            setState(() {
              _profileImages[accountId] = profileUrl;
            });
          } else {
            print('No profile image found for Twitter account: $username');
          }
        } catch (e) {
          print('Error loading Twitter profile for $username: $e');
        }
      }
      
      // Load TikTok profile images
      for (var account in _tiktokAccounts) {
        final accountId = account['id'] as String;
        final username = account['username'] ?? 'unknown';
        print('Loading TikTok profile image for $username (ID: $accountId)');
        
        try {
          // Check in users/[uid]/tiktok/[accountId]
          final snapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child(currentUser.uid)
              .child('tiktok')
              .child(accountId)
              .child('profile_image_url')
              .get();
          
          if (snapshot.exists && snapshot.value != null) {
            final profileUrl = snapshot.value as String;
            print('Found TikTok profile image: $profileUrl');
            setState(() {
              _profileImages[accountId] = profileUrl;
            });
            continue; // Skip other checks if found
          }
          
          // Check in users/users/[uid]/tiktok/[accountId]
          final altSnapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child('users')
              .child(currentUser.uid)
              .child('tiktok')
              .child(accountId)
              .child('profile_image_url')
              .get();
          
          if (altSnapshot.exists && altSnapshot.value != null) {
            final profileUrl = altSnapshot.value as String;
            print('Found TikTok profile image (alt path): $profileUrl');
            setState(() {
              _profileImages[accountId] = profileUrl;
            });
          } else {
            print('No profile image found for TikTok account: $username');
          }
        } catch (e) {
          print('Error loading TikTok profile for $username: $e');
        }
      }
      
      // Load Facebook profile images
      for (var account in _facebookAccounts) {
        final accountId = account['id'] as String;
        final username = account['username'] ?? 'unknown';
        print('Loading Facebook profile image for $username (ID: $accountId)');
        
        try {
          // Check in users/[uid]/facebook/[accountId]
          final snapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child(currentUser.uid)
              .child('facebook')
              .child(accountId)
              .child('profile_image_url')
              .get();
          
          if (snapshot.exists && snapshot.value != null) {
            final profileUrl = snapshot.value as String;
            print('Found Facebook profile image: $profileUrl');
            setState(() {
              _profileImages[accountId] = profileUrl;
            });
            continue; // Skip other checks if found
          }
          
          // Check in users/users/[uid]/facebook/[accountId]
          final altSnapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child('users')
              .child(currentUser.uid)
              .child('facebook')
              .child(accountId)
              .child('profile_image_url')
              .get();
          
          if (altSnapshot.exists && altSnapshot.value != null) {
            final profileUrl = altSnapshot.value as String;
            print('Found Facebook profile image (alt path): $profileUrl');
            setState(() {
              _profileImages[accountId] = profileUrl;
            });
          } else {
            print('No profile image found for Facebook account: $username');
          }
        } catch (e) {
          print('Error loading Facebook profile for $username: $e');
        }
      }
      
      // Load Threads profile images
      for (var account in _threadsAccounts) {
        final accountId = account['id'] as String;
        final username = account['username'] ?? 'unknown';
        print('Loading Threads profile image for $username (ID: $accountId)');
        
        try {
          // Check in users/users/[uid]/social_accounts/threads/[accountId]
          final snapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child('users')
              .child(currentUser.uid)
              .child('social_accounts')
              .child('threads')
              .child(accountId)
              .child('profile_image_url')
              .get();
          
          if (snapshot.exists && snapshot.value != null) {
            final profileUrl = snapshot.value as String;
            print('Found Threads profile image: $profileUrl');
            setState(() {
              _profileImages[accountId] = profileUrl;
            });
          } else {
            print('No profile image found for Threads account: $username');
          }
        } catch (e) {
          print('Error loading Threads profile for $username: $e');
        }
      }
      
      print('Finished loading profile images. Total loaded: ${_profileImages.length}');
    } catch (e) {
      print('Error in profile image loading process: $e');
    }
  }
  
  // Try to load remaining profile images from main social_accounts node
  Future<void> _loadRemainingProfileImages(String userId) async {
    try {
      final socialAccountsSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(userId)
          .child('social_accounts')
          .get();
      
      if (!socialAccountsSnapshot.exists) return;
      
      final socialAccounts = socialAccountsSnapshot.value as Map<dynamic, dynamic>;
      
      // Process each platform's accounts
      for (var platformEntry in socialAccounts.entries) {
        final platform = platformEntry.key.toString();
        if (platformEntry.value is! Map) continue;
        
        final accounts = platformEntry.value as Map<dynamic, dynamic>;
        
        // Process each account in this platform
        for (var accountEntry in accounts.entries) {
          final accountId = accountEntry.key.toString();
          if (accountEntry.value is! Map) continue;
          
          final accountData = accountEntry.value as Map<dynamic, dynamic>;
          
          // Only process if we don't already have a profile image for this account
          if (!_profileImages.containsKey(accountId) || _profileImages[accountId] == null) {
            // Look for profile image in various fields
            final possibleFields = [
              'profile_picture', 
              'profile_image_url', 
              'profile_pic',
              'profile_image'
            ];
            
            for (var field in possibleFields) {
              if (accountData.containsKey(field) && 
                  accountData[field] != null && 
                  accountData[field].toString().isNotEmpty) {
                final imageUrl = accountData[field].toString();
                print('Found profile image for $platform account $accountId: $imageUrl');
                
                setState(() {
                  _profileImages[accountId] = imageUrl;
                });
                break;
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error loading remaining profile images: $e');
    }
  }

  // Add this method to save upload history to Firebase
  Future<void> _saveUploadHistory() async {
    try {
      // Prevent duplicate saving
      if (_uploadHistorySaved) {
        print('Upload history already saved, skipping');
        return;
      }
      
      // Check if we're still mounted and user is authenticated
      if (!mounted || (_cloudflareUrl == null && _cloudflareUrls.isEmpty)) return;
      
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('Error saving upload history: User not authenticated');
        return;
      }
      
      // Get completed accounts for each platform
      Map<String, List<Map<String, dynamic>>> completedAccounts = {};
      
      // For Instagram
      final instagramCompleted = _instagramAccounts.where(
        (account) => _accountComplete[account['id']] == true
      ).toList();
      if (instagramCompleted.isNotEmpty) {
        completedAccounts['Instagram'] = instagramCompleted;
      }
      
      // For YouTube
      final youtubeCompleted = _youtubeAccounts.where(
        (account) => _accountComplete[account['id']] == true
      ).toList();
      if (youtubeCompleted.isNotEmpty) {
        completedAccounts['YouTube'] = youtubeCompleted;
      }
      
      // For Twitter
      final twitterCompleted = _twitterAccounts.where(
        (account) => _accountComplete[account['id']] == true
      ).toList();
      if (twitterCompleted.isNotEmpty) {
        completedAccounts['Twitter'] = twitterCompleted;
      }
      
      // For Threads
      final threadsCompleted = _threadsAccounts.where(
        (account) => _accountComplete[account['id']] == true
      ).toList();
      if (threadsCompleted.isNotEmpty) {
        completedAccounts['Threads'] = threadsCompleted;
      }
      
      // For Facebook
      final facebookCompleted = _facebookAccounts.where(
        (account) => _accountComplete[account['id']] == true
      ).toList();
      if (facebookCompleted.isNotEmpty) {
        completedAccounts['Facebook'] = facebookCompleted;
      }
      
      // For TikTok
      final tiktokCompleted = _tiktokAccounts.where(
        (account) => _accountComplete[account['id']] == true
      ).toList();
      if (tiktokCompleted.isNotEmpty) {
        completedAccounts['TikTok'] = tiktokCompleted;
      }
      
      // If no accounts completed, don't save anything
      if (completedAccounts.isEmpty) {
        print('No completed accounts to save in history');
        return;
      }
      
      // Create list of platform names where posts were published
      List<String> platforms = completedAccounts.keys.toList();
      
      // Use complete account information for each platform with custom descriptions
      Map<String, List<Map<String, dynamic>>> accountsByPlatform = {};
      completedAccounts.forEach((platform, accounts) {
        // Create a list of fully detailed account objects with all available information
        List<Map<String, dynamic>> completeAccounts = accounts.map((account) {
          final accountId = account['id'] as String;
          
          // Get saved post_id and media_id for this account
          final savedPostId = _accountPostIds[accountId];
          final savedMediaId = _accountMediaIds[accountId];
          
          // Get custom title and description for this account if available
          String? customTitle;
          String? customDescription;
          
          // Use the same logic as post_scheduler_page.dart for determining custom descriptions
          // If there's a custom description in platformDescriptions, use it
          // Otherwise, use the global description ONLY if the user hasn't disabled the toggle
          if (widget.platformDescriptions != null && 
              widget.platformDescriptions.containsKey(platform) && 
              widget.platformDescriptions[platform]!.containsKey(accountId)) {
            final platformSpecificText = widget.platformDescriptions[platform]![accountId];
            if (platformSpecificText != null && platformSpecificText.isNotEmpty) {
              customDescription = platformSpecificText;
            }
            // If the custom description is empty, don't use the global one
            // (user has disabled the toggle and left the field empty)
          } else {
            // If there's no key for this account in platformDescriptions,
            // it means the user has disabled the toggle to use global content
            // Don't save any description
            customDescription = null;
          }
          
          // For custom title, check if there's a platform-specific title first
          if (widget.platformDescriptions.containsKey(platform) &&
              widget.platformDescriptions[platform]!.containsKey('${accountId}_title') &&
              widget.platformDescriptions[platform]!['${accountId}_title']!.isNotEmpty) {
            customTitle = widget.platformDescriptions[platform]!['${accountId}_title']!;
          } else if (widget.title != null && widget.title!.isNotEmpty) {
            customTitle = widget.title!;
          }
          
          // Build a complete account object with all important details
          Map<String, dynamic> accountData = {
            'id': accountId,
            'username': account['username'] ?? '',
            'display_name': account['display_name'] ?? '',
            'profile_image_url': account['profile_image_url'] ?? _profileImages[accountId] ?? '',
            'followers_count': account['followers_count'] ?? "0",
            // Add saved post_id and media_id if available
            'post_id': savedPostId ?? account['post_id'] ?? '',
            'media_id': savedMediaId ?? account['media_id'] ?? '',
          };
          
          // Add custom title and description if available
          if (customTitle != null) {
            accountData['title'] = customTitle;
          }
          if (customDescription != null) {
            accountData['description'] = customDescription;
          }
          
          // Add platform-specific fields
          if (platform == 'YouTube') {
            accountData['youtube_video_id'] = savedPostId; // For YouTube, post_id is the video ID
            // For YouTube, always save the title (custom or global)
            if (customTitle != null && customTitle.isNotEmpty) {
              accountData['title'] = customTitle;
            } else if (widget.title != null && widget.title!.isNotEmpty) {
              accountData['title'] = widget.title!;
            } else {
              accountData['title'] = ''; // Always save title field for YouTube
            }
            // For YouTube, handle description the same way as other platforms
            if (customDescription != null) {
              accountData['description'] = customDescription;
            } else {
              // If there's no custom description, don't save the global one
              // (user has disabled the toggle)
              accountData['description'] = null;
            }
          }
          
          return accountData;
        }).toList();
        
        accountsByPlatform[platform] = completeAccounts;
      });
      
      // Determina se siamo in modalità multi-media (carosello)
      final bool hasMultipleMedia = _mediaFiles.length > 1 && _cloudflareUrls.length > 1;

      // Get video duration solo se NON è carosello e non è immagine
      Map<String, int>? videoDuration;
      if (!hasMultipleMedia && !widget.isImageFile) {
        videoDuration = await _getVideoDuration();
      }
      
      // Create video entry data
      // Determine the title to save - prioritize platform-specific titles
      String finalTitle = widget.title;
      
      // Check if there are any platform-specific titles in platformDescriptions
      for (var platform in widget.platformDescriptions.keys) {
        for (var key in widget.platformDescriptions[platform]!.keys) {
          if (key.endsWith('_title') && widget.platformDescriptions[platform]![key]!.isNotEmpty) {
            // Use the first platform-specific title found
            finalTitle = widget.platformDescriptions[platform]![key]!;
            break;
          }
        }
        if (finalTitle != widget.title) break; // Found a platform-specific title
      }
      
      final videoData = {
        'title': finalTitle,
        'platforms': platforms,
        'status': 'published',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'video_path': _cloudflareUrl, // Use Cloudflare URL instead of local path
        'thumbnail_path': _thumbnailCloudflareUrl ?? _cloudflareUrl, // Use thumbnail URL if available, otherwise video URL
        'thumbnail_cloudflare_url': _thumbnailCloudflareUrl ?? _cloudflareUrl, // Keep this field for compatibility
        'cloudflare_url': _cloudflareUrl, // Add this field for completeness
        if (_cloudflareUrls.isNotEmpty) 'cloudflare_urls': _cloudflareUrls,
        'accounts': accountsByPlatform,
        'user_id': currentUser.uid,
        'is_image': widget.isImageFile,
        // Save platform-specific descriptions and titles
        'platform_descriptions': widget.platformDescriptions,
        // Add video duration information if available
        if (videoDuration != null) ...{
          'video_duration_seconds': videoDuration['total_seconds'],
          'video_duration_minutes': videoDuration['minutes'],
          'video_duration_remaining_seconds': videoDuration['seconds'],
        },
      };
      
      // Add global description only if it's not empty and no custom descriptions are used
      // This maintains backward compatibility while supporting custom descriptions
      if (widget.description != null && widget.description!.isNotEmpty) {
        // Only add global description if no custom descriptions are being used
        bool hasCustomDescriptions = false;
        for (var platform in accountsByPlatform.keys) {
          for (var account in accountsByPlatform[platform]!) {
            if (account['description'] != null && account['description'].toString().isNotEmpty) {
              hasCustomDescriptions = true;
              break;
            }
          }
          if (hasCustomDescriptions) break;
        }
        
        if (!hasCustomDescriptions) {
          videoData['description'] = widget.description;
        }
      }
      
      // Generate a unique ID for the video entry
      final videoId = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .push()
          .key;
      
      if (videoId == null) {
        print('Error generating video ID');
        return;
      }
      
      // Save to Firebase
      await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .child(videoId)
          .set(videoData);
      
      // Mark that we've saved the history to prevent duplicates
      _uploadHistorySaved = true;
      
      print('Upload history saved successfully with ID: $videoId');
      print('✅ [INSTAGRAM_UPLOAD_FIREBASE] Post salvato con path: users/users/${currentUser.uid}/videos/$videoId');
      print('✅ [INSTAGRAM_UPLOAD_FIREBASE] Custom descriptions applied for ${accountsByPlatform.length} platforms');
      
      // Delete the draft if it exists (when publishing from a draft)
      if (widget.draftId != null && widget.draftId!.isNotEmpty) {
        await _deleteDraft(widget.draftId!);
      }
    } catch (e) {
      print('Error saving upload history: $e');
    }
  }

  // Method to delete draft from Firebase
  Future<void> _deleteDraft(String draftId) async {
    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('Error deleting draft: User not authenticated');
        return;
      }
      
      // Delete the draft from Firebase
      await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .child(draftId)
          .remove();
      
      print('Draft deleted successfully with ID: $draftId');
    } catch (e) {
      print('Error deleting draft: $e');
    }
  }

  // Method to deduct credits from user account
  Future<void> _deductCredits() async {
    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('Error deducting credits: User not authenticated');
        return;
      }

      // Calcola i crediti da sottrarre in base alla dimensione TOTALE di tutti i media
      int totalBytes = 0;
      if (_mediaFiles.isNotEmpty) {
        for (final file in _mediaFiles) {
          try {
            totalBytes += file.lengthSync();
          } catch (e) {
            print('Errore nel leggere la dimensione del file per i crediti: $e');
          }
        }
      } else {
        // Fallback: usa il singolo mediaFile
        totalBytes = widget.mediaFile.lengthSync();
      }

      final fileSizeMB = totalBytes / (1024 * 1024);
      final creditsToDeduct = (fileSizeMB * 0.4).ceil();
      
      print('Deducting credits - file size: ${fileSizeMB.toStringAsFixed(2)}MB, credits to deduct: $creditsToDeduct');
      
      // Get current user credits
      final userRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(currentUser.uid);
          
      final creditsSnapshot = await userRef.child('credits').get();
      
      if (!mounted) return;
      
      // Get current credits
      int currentCredits = 0;
      if (creditsSnapshot.exists) {
        currentCredits = (creditsSnapshot.value as int?) ?? 0;
      }
      
      print('Current credits before deduction: $currentCredits');
      
      // Calculate new credits (don't go below 0)
      int newCredits = (currentCredits - creditsToDeduct).clamp(0, double.infinity).toInt();
      
      // Update credits in Firebase
      await userRef.child('credits').set(newCredits);
      
      // Update local variable
      _creditsDeducted = creditsToDeduct;
      
      print('Credits deducted: $creditsToDeduct. New balance: $newCredits');
    } catch (e) {
      print('Error deducting credits: $e');
    }
  }
  
  // Upload thumbnail to Cloudflare R2
  Future<String?> _uploadThumbnailToCloudflare() async {
    if (_thumbnailPath == null) {
      print('No thumbnail to upload');
      return null;
    }
    
    try {
      final File thumbnailFile = File(_thumbnailPath!);
      if (!await thumbnailFile.exists()) {
        print('Thumbnail file not found: $_thumbnailPath');
        return null;
      }
      
      // Generate a unique filename for the thumbnail
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Utente non autenticato');
      }
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final String thumbnailFileName = 'thumb_${timestamp}_${currentUser.uid}.jpg';
      
      // Cloudflare R2 credentials
      final String accessKeyId = '5e181628bad7dc5481c92c6f3899efd6';
      final String secretKey = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
      final String endpoint = 'https://3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com';
      final String bucketName = 'videos';
      final String accountId = '3d945eb681944ec5965fecf275e41a9b';
      final String region = 'auto';
      
      // Get file bytes and size
      final bytes = await thumbnailFile.readAsBytes();
      final contentLength = bytes.length;
      
      // Calculate SHA-256 hash of content
      final List<int> contentHash = sha256.convert(bytes).bytes;
      final String payloadHash = hex.encode(contentHash);
      
      // Set up request information
      final String httpMethod = 'PUT';
      final String contentType = 'image/jpeg';
      
      // SigV4 requires date in ISO8601 format
      final now = DateTime.now().toUtc();
      final String amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
      final String dateStamp = DateFormat("yyyyMMdd").format(now);
      
      // Host and URI
      final Uri uri = Uri.parse('$endpoint/$bucketName/$thumbnailFileName');
      final String host = uri.host;
      
      // Canonical request
      final Map<String, String> headers = {
        'host': host,
        'content-type': contentType,
        'x-amz-content-sha256': payloadHash,
        'x-amz-date': amzDate
      };
      
      String canonicalHeaders = '';
      String signedHeaders = '';
      
      // Sort headers lexicographically
      final sortedHeaderKeys = headers.keys.toList()..sort();
      for (final key in sortedHeaderKeys) {
        canonicalHeaders += '${key.toLowerCase()}:${headers[key]}\n';
        signedHeaders += '${key.toLowerCase()};';
      }
      signedHeaders = signedHeaders.substring(0, signedHeaders.length - 1);
      
      // Canonical request
      final String canonicalUri = '/$bucketName/$thumbnailFileName';
      final String canonicalQueryString = '';
      final String canonicalRequest = '$httpMethod\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
      
      // String to sign
      final String algorithm = 'AWS4-HMAC-SHA256';
      final String scope = '$dateStamp/$region/s3/aws4_request';
      final String stringToSign = '$algorithm\n$amzDate\n$scope\n${hex.encode(sha256.convert(utf8.encode(canonicalRequest)).bytes)}';
      
      // Signature
      List<int> getSignatureKey(String key, String dateStamp, String regionName, String serviceName) {
        final kDate = Hmac(sha256, utf8.encode('AWS4$key')).convert(utf8.encode(dateStamp)).bytes;
        final kRegion = Hmac(sha256, kDate).convert(utf8.encode(regionName)).bytes;
        final kService = Hmac(sha256, kRegion).convert(utf8.encode(serviceName)).bytes;
        final kSigning = Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
        return kSigning;
      }
      
      final signingKey = getSignatureKey(secretKey, dateStamp, region, 's3');
      final signature = hex.encode(Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).bytes);
      
      // Authorization header
      final String authorizationHeader = '$algorithm Credential=$accessKeyId/$scope, SignedHeaders=$signedHeaders, Signature=$signature';
      
      // Create request URL
      final String uploadUrl = '$endpoint/$bucketName/$thumbnailFileName';
      
      // Create request with headers
      final http.Request request = http.Request('PUT', Uri.parse(uploadUrl));
      request.headers['Host'] = host;
      request.headers['Content-Type'] = contentType;
      request.headers['Content-Length'] = contentLength.toString();
      request.headers['X-Amz-Content-Sha256'] = payloadHash;
      request.headers['X-Amz-Date'] = amzDate;
      request.headers['Authorization'] = authorizationHeader;
      
      // Add file body
      request.bodyBytes = bytes;
      
      // Send the request
      final response = await http.Client().send(request);
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Generate public URL in the correct format
        final String publicUrl = 'https://pub-$accountId.r2.dev/$thumbnailFileName';
        
        print('Thumbnail uploaded successfully to Cloudflare R2');
        print('Thumbnail URL: $publicUrl');
        
        _thumbnailCloudflareUrl = publicUrl;
        return publicUrl;
      } else {
        throw Exception('Error uploading thumbnail to Cloudflare R2: Code ${response.statusCode}, Response: $responseBody');
      }
    } catch (e) {
      print('Error uploading thumbnail to Cloudflare: $e');
      return null;
    }
  }

  // Metodo per calcolare i crediti sottratti
  int _calculateCreditsDeducted() {
    try {
      // Calcola la dimensione TOTALE dei file in megabyte (carosello incluso)
      int totalBytes = 0;
      if (_mediaFiles.isNotEmpty) {
        for (final file in _mediaFiles) {
          try {
            totalBytes += file.lengthSync();
          } catch (e) {
            print('Errore nel leggere la dimensione del file per il calcolo crediti: $e');
          }
        }
      } else {
        // Fallback: usa il singolo mediaFile
        totalBytes = widget.mediaFile.lengthSync();
      }

      final fileSizeMB = totalBytes / (1024 * 1024);
      
      // Moltiplica per 0.40 e arrotonda per eccesso
      final creditsToDeduct = (fileSizeMB * 0.40).ceil();
      
      return creditsToDeduct;
    } catch (e) {
      print('Errore nel calcolo dei crediti: $e');
      return 1; // Valore di default in caso di errore
    }
  }

  // Metodo per verificare se l'utente è premium e ottenere i crediti attuali
  Future<void> _checkUserPremiumStatus() async {
    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final userSnapshot = await FirebaseDatabase.instance.ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .get();

      if (userSnapshot.exists) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        final isPremium = userData['isPremium'] == true;
        final currentCredits = userData['credits'] ?? 0;
        
        print('User premium status check - isPremium: $isPremium, credits: $currentCredits');
        
        setState(() {
          _isPremium = isPremium;
          _currentCredits = currentCredits;
        });
      }
    } catch (e) {
      print('Errore nel controllo dello status premium: $e');
    }
  }

  // Metodo per mostrare il popup di successo per utenti non premium
  void _showNonPremiumSuccessDialog() {
    // Calcola i crediti sottratti
    final fileSizeBytes = widget.mediaFile.lengthSync();
    final fileSizeMB = fileSizeBytes / (1024 * 1024);
    final creditsDeducted = (fileSizeMB * 0.4).ceil();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header con icona di successo
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF6C63FF).withOpacity(0.1),
                        Color(0xFFFF6B6B).withOpacity(0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF6C63FF),
                              Color(0xFFFF6B6B),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFF6C63FF).withOpacity(0.3),
                              blurRadius: 15,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                      SizedBox(height: 24),
                      Text(
                        'Upload Successful!',
                        style: TextStyle(
                          color: Color(0xFF2C2C3E),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Your content has been published successfully',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                // Sezione pulsanti (senza crediti)
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      // Pulsante View History
                      Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                            stops: [0.0, 1.0],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFF6C63FF).withOpacity(0.3),
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.of(context).pop();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const HistoryPage(initialTabIndex: 1),
                                ),
                              );
                            },
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.history,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'View History',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      // Pulsante Continue
                      Container(
                        width: double.infinity,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                            stops: [0.0, 1.0],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              print('Continue button tapped, navigating to home with showUpgradePopup: true');
                              Navigator.of(context).pop();
                              Navigator.pushNamedAndRemoveUntil(
                                context,
                                '/',
                                (route) => false,
                                arguments: {'showUpgradePopup': true},
                              );
                            },
                            child: Center(
                              child: Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
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
        );
      },
    );
  }

  // Metodo per mostrare il popup di successo per utenti premium
  void _showPremiumSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header con icona di successo
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF6C63FF).withOpacity(0.1),
                        Color(0xFFFF6B6B).withOpacity(0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF6C63FF),
                              Color(0xFFFF6B6B),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFF6C63FF).withOpacity(0.3),
                              blurRadius: 15,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                      SizedBox(height: 24),
                      Text(
                        'Upload Successful!',
                        style: TextStyle(
                          color: Color(0xFF2C2C3E),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Your content has been published successfully',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                // Sezione pulsanti (senza crediti)
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      // Pulsante View History
                      Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                            stops: [0.0, 1.0],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFF6C63FF).withOpacity(0.3),
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.of(context).pop();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const HistoryPage(initialTabIndex: 1),
                                ),
                              );
                            },
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.history,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'View History',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      // Pulsante Continue
                      Container(
                        width: double.infinity,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                            stops: [0.0, 1.0],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.of(context).pop();
                              Navigator.pushNamedAndRemoveUntil(
                                context,
                                '/',
                                (route) => false,
                              );
                            },
                            child: Center(
                              child: Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
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
        );
      },
    );
  }

  // Function to show TikTok audit dialog
  void _showTikTokAuditDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF00F2EA).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.info_outline,
                color: Color(0xFF00F2EA),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'TikTok Audit Required',
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
            const Text(
              'Your TikTok app is LIVE but requires an additional audit to publish public content.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'App Status: LIVE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.pending_outlined,
                        size: 18,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Content Sharing: Pending Audit',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'How to complete the audit:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '1. Go to developers.tiktok.com\n'
              '2. Select your app "Fluzar"\n'
              '3. Click "App review" → "Content Sharing"\n'
              '4. Fill out the audit form\n'
              '5. Wait for approval (1–3 days)',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'OK',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Function to get video duration in seconds and minutes
  Future<Map<String, int>?> _getVideoDuration() async {
    if (widget.isImageFile) {
      return null; // Non serve per le immagini
    }
    
    try {
      final VideoPlayerController controller = VideoPlayerController.file(widget.mediaFile);
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
} 