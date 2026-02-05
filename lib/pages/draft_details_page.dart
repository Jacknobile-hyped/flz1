import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:ui'; // Aggiunto per ImageFilter
import 'package:firebase_database/firebase_database.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:twitter_api_v2/twitter_api_v2.dart' as v2;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import 'upload_video_page.dart';
import 'social/social_account_details_page.dart';

class DraftDetailsPage extends StatefulWidget {
  final Map<String, dynamic> video;

  const DraftDetailsPage({
    super.key,
    required this.video,
  });

  @override
  State<DraftDetailsPage> createState() => _DraftDetailsPageState();
}

class _DraftDetailsPageState extends State<DraftDetailsPage> with SingleTickerProviderStateMixin {
  bool _isPublishing = false;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  Map<String, List<Map<String, dynamic>>> _socialAccounts = {};
  bool _isLoading = true;
  
  // Tab controller e page controller per le sezioni
  late TabController _tabController;
  final PageController _pageController = PageController();
  int _currentPage = 0;
  
  // Video player related variables
  VideoPlayerController? _videoPlayerController;
  bool _isPlaying = false;
  bool _isVideoInitialized = false;
  bool _isDisposed = false;
  Timer? _autoplayTimer;
  bool _showControls = false;
  bool _isFullScreen = false;
  Duration _currentPosition = Duration.zero;
  Duration _videoDuration = Duration.zero;
  Timer? _positionUpdateTimer;
  Map<String, dynamic>? _videoDetails;
  
  // Carousel related variables for multi-media
  List<String> _mediaUrls = [];
  List<bool> _isImageList = [];
  PageController? _carouselController;
  int _currentCarouselIndex = 0;
  String? _currentVideoUrl; // Track current video URL to avoid re-initializing unnecessarily

  final Map<String, String> _platformLogos = {
    'twitter': 'assets/loghi/logo_twitter.png',
    'youtube': 'assets/loghi/logo_yt.png',
    'tiktok': 'assets/loghi/logo_tiktok.png',
    'instagram': 'assets/loghi/logo_insta.png',
    'facebook': 'assets/loghi/logo_facebook.png',
    'threads': 'assets/loghi/threads_logo.png',
  };

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
    
    _loadSocialAccounts();
    _loadVideoDetails().then((_) {
      // Only initialize player if single media and not an image
      final hasMultipleMedia = _mediaUrls.length > 1;
      if (!hasMultipleMedia && !_isImage) {
        _initializePlayer();
      }
      if (!hasMultipleMedia) {
        _startPositionUpdateTimer();
        setState(() {
          _showControls = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _autoplayTimer?.cancel();
    _positionUpdateTimer?.cancel();
    _tabController.dispose();
    _pageController.dispose();
    _carouselController?.dispose();
    if (_videoPlayerController != null) {
      _videoPlayerController!.removeListener(_onVideoPositionChanged);
      _videoPlayerController!.dispose();
    }
    super.dispose();
  }

  // Check if the content is an image
  bool get _isImage => widget.video['is_image'] == true;

  String? _getVideoTitle() {
    // Try to get the title from the title field
    final title = widget.video['title'] as String?;
    if (title != null && !title.endsWith('.mp4')) {
      return title;
    }
    
    // If the title is not present or is the file name, use the description
    final description = widget.video['description'] as String?;
    if (description != null) {
      final titleFromDesc = description.split('#').first.trim();
      if (titleFromDesc.isNotEmpty) {
        return titleFromDesc;
      }
    }
    
    // If there is no title or description, use the file name
    return title;
  }

  Future<void> _loadVideoDetails() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Load video data directly from Firebase to ensure we have all fields including cloudflare_urls
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final videoId = widget.video['id'] as String?;
        if (videoId != null) {
          final videoSnapshot = await _database
              .child('users')
              .child('users')
              .child(currentUser.uid)
              .child('videos')
              .child(videoId)
              .get();
          
          if (videoSnapshot.exists) {
            final videoData = videoSnapshot.value as Map<dynamic, dynamic>?;
            if (videoData != null) {
              // Convert dynamic map to Map<String, dynamic>
              final Map<String, dynamic> videoMap = {};
              videoData.forEach((key, value) {
                videoMap[key.toString()] = value;
              });
              
              // Load video_paths separately if it exists as a nested list
              try {
                final videoPathsSnapshot = await _database
                    .child('users')
                    .child('users')
                    .child(currentUser.uid)
                    .child('videos')
                    .child(videoId)
                    .child('video_paths')
                    .get();
                
                if (videoPathsSnapshot.exists) {
                  final videoPathsData = videoPathsSnapshot.value;
                  if (videoPathsData is List) {
                    // Convert list to List<String>
                    final List<String> videoPathsList = videoPathsData.map((e) => e.toString()).toList();
                    videoMap['video_paths'] = videoPathsList;
                    print('Loaded video_paths from Firebase: ${videoPathsList.length} items');
                  } else if (videoPathsData is Map) {
                    // If it's a map (indexed list like 0, 1, 2, ...), convert to list maintaining order
                    final List<MapEntry<dynamic, dynamic>> entries = videoPathsData.entries.toList();
                    // Sort by key (convert to int if possible, otherwise use string comparison)
                    entries.sort((a, b) {
                      final aKey = a.key;
                      final bKey = b.key;
                      if (aKey is int && bKey is int) {
                        return aKey.compareTo(bKey);
                      }
                      final aKeyStr = aKey.toString();
                      final bKeyStr = bKey.toString();
                      final aInt = int.tryParse(aKeyStr);
                      final bInt = int.tryParse(bKeyStr);
                      if (aInt != null && bInt != null) {
                        return aInt.compareTo(bInt);
                      }
                      return aKeyStr.compareTo(bKeyStr);
                    });
                    final List<String> videoPathsList = entries
                        .where((entry) => entry.value != null)
                        .map((entry) => entry.value.toString())
                        .toList();
                    videoMap['video_paths'] = videoPathsList;
                    print('Loaded video_paths from Firebase (map format): ${videoPathsList.length} items');
                  }
                }
              } catch (e) {
                print('Error loading video_paths: $e');
                // Continue without video_paths if there's an error
              }
              
              setState(() {
                _videoDetails = videoMap;
              });
              
              print('Loaded video data from Firebase: ${videoMap.keys.toList()}');
              print('cloudflare_urls in loaded data: ${videoMap['cloudflare_urls']}');
              print('video_paths in loaded data: ${videoMap['video_paths']}');
            }
          }
        }
      }
      
      // Fallback to widget.video if Firebase load fails
      if (_videoDetails == null) {
        setState(() {
          _videoDetails = widget.video;
        });
      }
      
      setState(() {
        _isLoading = false;
      });
      
      // Check if we have cloudflare_urls (carousel) - PRIORITIZE cloudflare_urls over cloudflare_url
      // Use _videoDetails if available, otherwise widget.video
      final videoDataToCheck = _videoDetails ?? widget.video;
      final cloudflareUrls = videoDataToCheck['cloudflare_urls'] as List<dynamic>?;
      
      print('Checking cloudflare_urls - videoDataToCheck keys: ${videoDataToCheck.keys.toList()}');
      print('cloudflare_urls type: ${cloudflareUrls.runtimeType}, value: $cloudflareUrls');
      
      if (cloudflareUrls != null && cloudflareUrls.isNotEmpty) {
        print('Found cloudflare_urls with ${cloudflareUrls.length} items');
        // Populate media lists
        _mediaUrls = cloudflareUrls.cast<String>();
        
        // Determine which are images and which are videos
        // Since we can't download and check files, we'll use heuristics:
        // - Check URL extensions or default to video if no extension info
        // - For now, assume all are videos unless we have explicit image info
        _isImageList = List.generate(_mediaUrls.length, (index) {
          final url = _mediaUrls[index].toLowerCase();
          // Simple heuristic: check if URL contains image extensions
          return url.contains('.jpg') || 
                 url.contains('.jpeg') || 
                 url.contains('.png') || 
                 url.contains('.gif') ||
                 url.contains('.webp') ||
                 url.contains('.bmp') ||
                 url.contains('.heic') ||
                 url.contains('.heif');
        });
        
        print('Populated _mediaUrls with ${_mediaUrls.length} items, isImageList: $_isImageList');
        
        // Initialize carousel controller if we have cloudflare_urls (even with 1 item to avoid conflicts with cloudflare_url)
        if (_mediaUrls.isNotEmpty) {
          _carouselController = PageController(initialPage: 0);
          print('Initialized carousel controller for ${_mediaUrls.length} media');
        }
        
        // Initialize player for first media if it's a video
        if (_mediaUrls.isNotEmpty && !_isImageList[0]) {
          // Initialize video player for first video in carousel
          final firstVideoUrl = _mediaUrls[0];
          _currentVideoUrl = firstVideoUrl;
          _initializeNetworkVideoPlayer(firstVideoUrl);
        } else if (_mediaUrls.isNotEmpty && _isImageList[0]) {
          // If first media is an image, clear video URL
          _currentVideoUrl = null;
        }
      } else {
        // Single media - use existing logic
        print('No cloudflare_urls found, using single media logic');
        _mediaUrls = [];
        _isImageList = [];
      }
      
      // For images, no need to initialize the player
      if (_isImage) {
        print("Content is an image, skipping video player initialization");
      }
    } catch (e) {
      print('Error loading content details: $e');
      setState(() {
        _isLoading = false;
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

  // Function to show controls temporarily
  void _showControlsTemporarily() {
    setState(() {
      _showControls = true;
    });
    
    // Auto-hide controls after 3 seconds if video is playing
    Future.delayed(Duration(seconds: 3), () {
      if (mounted && !_isDisposed && _isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  Future<void> _loadSocialAccounts() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Load Twitter accounts
      final twitterSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .get();
      
      if (twitterSnapshot.exists) {
        final twitterData = twitterSnapshot.value as Map<dynamic, dynamic>;
        final twitterAccounts = twitterData.entries.map((entry) {
          final accountData = entry.value as Map<dynamic, dynamic>;
          return {
            'id': entry.key,
            'username': accountData['username'] ?? '',
            'display_name': accountData['display_name'] ?? '',
            'profile_image_url': accountData['profile_image_url'] ?? '',
            'followers_count': accountData['followers_count']?.toString() ?? '0',
            'access_token': accountData['access_token'],
            'access_token_secret': accountData['access_token_secret'],
            'bearer_token': accountData['bearer_token'],
          };
        }).where((account) => account['username'].toString().isNotEmpty).toList();

        setState(() {
          _socialAccounts['Twitter'] = twitterAccounts;
        });
      }

      // Load YouTube accounts
      final youtubeSnapshot = await _database
          .child('users')
          .child(currentUser.uid)
          .child('youtube')
          .get();
      
      if (youtubeSnapshot.exists) {
        final youtubeData = youtubeSnapshot.value as Map<dynamic, dynamic>;
        final youtubeAccounts = youtubeData.entries.map((entry) {
          final accountData = entry.value as Map<dynamic, dynamic>;
          if (accountData['status'] != 'active') return null;
          return {
            'id': entry.key,
            'username': accountData['channel_name'] ?? '',
            'display_name': accountData['channel_name'] ?? '',
            'profile_image_url': accountData['thumbnail_url'] ?? '',
            'followers_count': accountData['subscriber_count']?.toString() ?? '0',
            'channel_id': accountData['channel_id'] ?? '',
            'video_count': accountData['video_count']?.toString() ?? '0',
          };
        }).where((account) => account != null).cast<Map<String, dynamic>>().toList();

        setState(() {
          _socialAccounts['YouTube'] = youtubeAccounts;
        });
      }
    } catch (e) {
      print('Error loading social accounts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading social accounts: $e')),
        );
      }
    }
  }

  Future<void> _publishVideo() async {
    if (_isPublishing) return;

    setState(() {
      _isPublishing = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Get the video data
      final videoData = widget.video;
      final accounts = videoData['accounts'] as Map<String, dynamic>;
      final platforms = videoData['platforms'] as List<dynamic>;

      // Upload to each platform
      for (var platform in platforms) {
        final platformAccounts = accounts[platform.toString().toLowerCase()] as List<dynamic>;
        for (var account in platformAccounts) {
          switch (platform.toString().toLowerCase()) {
            case 'twitter':
              await _uploadToTwitter(account);
              break;
            case 'youtube':
              await _uploadToYouTube(account);
              break;
            case 'tiktok':
              await _uploadToTikTok(account);
              break;
            case 'instagram':
              await _uploadToInstagram(account);
              break;
            case 'facebook':
              await _uploadToFacebook(account);
              break;
            case 'threads':
              await _uploadToThreads(account);
              break;
          }
        }
      }

      // Update video status to published
      await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .child(widget.video['id'])
          .update({
        'status': 'published',
        'published_at': DateTime.now().millisecondsSinceEpoch,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video published successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error publishing video: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPublishing = false;
        });
      }
    }
  }

  Future<void> _uploadToTwitter(Map<String, dynamic> account) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Initialize Twitter API
      final twitter = v2.TwitterApi(
        bearerToken: '',  // Empty bearer token to force OAuth 1.0a
        oauthTokens: v2.OAuthTokens(
          consumerKey: 'sTn3lkEWn47KiQl41zfGhjYb4',
          consumerSecret: 'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA',
          accessToken: account['access_token'] ?? '',
          accessTokenSecret: account['access_token_secret'] ?? '',
        ),
      );

      // Upload media
      final uploadResponse = await twitter.media.uploadMedia(
        file: File(widget.video['video_path']),
      );

      if (uploadResponse.data == null) {
        throw Exception('Failed to upload media to Twitter');
      }

      // Create tweet
      final tweet = await twitter.tweets.createTweet(
        text: widget.video['description'],
        media: v2.TweetMediaParam(
          mediaIds: [uploadResponse.data!.id],
        ),
      );

      if (tweet.data != null) {
        // Update account data with tweet ID
        await _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('social_accounts')
            .child('twitter')
            .child(account['id'])
            .update({
          'last_tweet_id': tweet.data.id,
        });
      }
    } catch (e) {
      print('Error during Twitter upload: $e');
      rethrow;
    }
  }

  Future<void> _uploadToYouTube(Map<String, dynamic> account) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Initialize Google Sign-In
      final GoogleSignIn _googleSignIn = GoogleSignIn(
        scopes: [
          'https://www.googleapis.com/auth/youtube.upload',
          'https://www.googleapis.com/auth/youtube.readonly',
          'https://www.googleapis.com/auth/youtube'
        ],
        clientId: '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com',
      );

      // Sign in with Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Google sign in cancelled');
      }

      // Get authentication details
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      if (googleAuth.accessToken == null) {
        throw Exception('Failed to get access token');
      }

      // Prepare video metadata
      final videoTitle = widget.video['title'] ?? widget.video['video_path'].split('/').last;
      final videoMetadata = {
        'snippet': {
          'title': videoTitle,
          'description': widget.video['description'],
          'categoryId': '22', // People & Blogs category
        },
        'status': {
          'privacyStatus': 'public',
          'madeForKids': false,
        }
      };

      // Upload video
      final uploadResponse = await http.post(
        Uri.parse('https://www.googleapis.com/upload/youtube/v3/videos?part=snippet,status'),
        headers: {
          'Authorization': 'Bearer ${googleAuth.accessToken}',
          'Content-Type': 'application/octet-stream',
          'X-Upload-Content-Type': 'video/*',
          'X-Upload-Content-Length': File(widget.video['video_path']).lengthSync().toString(),
        },
        body: await File(widget.video['video_path']).readAsBytes(),
      );

      if (uploadResponse.statusCode != 200) {
        throw Exception('Failed to upload video: ${uploadResponse.body}');
      }

      final videoData = json.decode(uploadResponse.body);
      final videoId = videoData['id'];

      // Update video metadata
      final metadataResponse = await http.put(
        Uri.parse('https://www.googleapis.com/youtube/v3/videos?part=snippet,status'),
        headers: {
          'Authorization': 'Bearer ${googleAuth.accessToken}',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'id': videoId,
          ...videoMetadata,
        }),
      );

      if (metadataResponse.statusCode != 200) {
        throw Exception('Failed to update video metadata: ${metadataResponse.body}');
      }

      // Update account data
      await _database
          .child('users')
          .child(currentUser.uid)
          .child('youtube')
          .child(account['id'])
          .update({
        'video_count': (account['video_count'] ?? 0) + 1,
        'last_sync': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('Error during YouTube upload: $e');
      rethrow;
    }
  }

  Future<void> _uploadToTikTok(Map<String, dynamic> account) async {
    // Implementation similar to upload_video_page.dart
    // ... existing TikTok upload code ...
  }

  Future<void> _uploadToInstagram(Map<String, dynamic> account) async {
    // Implementation similar to upload_video_page.dart
    // ... existing Instagram upload code ...
  }

  Future<void> _uploadToFacebook(Map<String, dynamic> account) async {
    // Implementation similar to upload_video_page.dart
    // ... existing Facebook upload code ...
  }

  Future<void> _uploadToThreads(Map<String, dynamic> account) async {
    // Implementation similar to upload_video_page.dart
    // ... existing Snapchat upload code ...
  }

  void _initializePlayer() {
    print("Initialize player called");
    
    if (_videoDetails == null) {
      print("Video details is null");
      return;
    }
    
    // Skip video initialization for images
    if (_isImage) {
      print('Content is an image, skipping video player initialization');
      return;
    }
    
    final videoPath = _videoDetails!['video_path'] as String?;
    if (videoPath == null || videoPath.isEmpty) {
      print("Video path is null or empty");
      return;
    }
    
    // Check if the file exists
    final videoFile = File(videoPath);
    if (!videoFile.existsSync()) {
      print('Video file not found: $videoPath, trying cloudflare_url');
      
      // If not local, check if we have a Cloudflare URL
      final cloudflareUrl = _videoDetails!['cloudflare_url'] as String?;
      if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
        print('Using Cloudflare URL for preview: $cloudflareUrl');
        
        // For now, we can't initialize the player with a URL
        setState(() {
          _isVideoInitialized = false;
        });
        
        // Show a message to the user
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local video is no longer available. Only preview will be shown.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      } else {
        print('No video resource available (neither local nor remote)');
        return;
      }
    }
    
    // Clean up any existing controller first
    if (_videoPlayerController != null) {
      print("Disposing existing controller");
      _videoPlayerController!.removeListener(_onVideoPositionChanged);
      _videoPlayerController!.dispose();
    }
    
    setState(() {
      _isVideoInitialized = false;
      _showControls = true; // Show controls when initializing
      _isPlaying = false; // Reset playing state
    });
    
    try {
      print("Creating new video controller");
      // Initialize the controller with the local video file
      _videoPlayerController = VideoPlayerController.file(videoFile);
      
      // Add listener for player events
      _videoPlayerController!.addListener(_onVideoPositionChanged);
      
      _videoPlayerController!.initialize().then((_) {
        print("Video controller initialized successfully");
        if (!mounted || _isDisposed) return;
        
        // Determine if the video is horizontal (aspect ratio > 1)
        final bool isHorizontalVideo = _videoPlayerController!.value.aspectRatio > 1.0;
        
        print("Video aspect ratio: ${_videoPlayerController!.value.aspectRatio}");
        print("Is horizontal video: $isHorizontalVideo");
        
        setState(() {
          _isVideoInitialized = true;
          _videoDuration = _videoPlayerController!.value.duration;
          _currentPosition = Duration.zero;
          _showControls = true; // Keep controls visible
        });
        
      }).catchError((error) {
        print('Error initializing video player: $error');
        
        // Handle errors properly
        setState(() {
          _isVideoInitialized = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to play video: ${error.toString().substring(0, min(error.toString().length, 50))}...'),
            duration: Duration(seconds: 3),
          ),
        );
      });
    } catch (e) {
      print('Exception during video controller creation: $e');
      
      setState(() {
        _isVideoInitialized = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating video player: ${e.toString().substring(0, min(e.toString().length, 50))}...'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _toggleVideoPlayback() {
    print("Toggle video playback called");
    
    if (_videoPlayerController == null) {
      print("Controller is null, initializing");
      _initializePlayer();
      return;
    }
    
    if (!_videoPlayerController!.value.isInitialized) {
      print("Controller not initialized");
      return;
    }
    
    if (_videoPlayerController!.value.isPlaying) {
      print("Pausing video");
      _videoPlayerController!.pause();
      _autoplayTimer?.cancel();
      setState(() {
        _isPlaying = false;
        _showControls = true; // Show controls when paused
      });
    } else {
      print("Playing video");
      // Retry play if there's an error or player is at end
      if (_videoPlayerController!.value.position >= _videoPlayerController!.value.duration) {
        // If the video has ended, restart from the beginning
        _videoPlayerController!.seekTo(Duration.zero);
      }
      
      _videoPlayerController!.play().then((_) {
        // Update state only if play succeeded
        if (mounted && !_isDisposed) {
          print("Play succeeded");
          setState(() {
            _isPlaying = true;
          });
        }
      }).catchError((error) {
        print('Error playing video: $error');
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

  Widget _buildImagePreview(String imagePath) {
    final imageFile = File(imagePath);
    
    // Check if local file exists
    if (imageFile.existsSync()) {
      return Image.file(
        imageFile,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          print('Error loading local image: $error, trying Cloudflare URL');
          // If local file fails, try Cloudflare URL
          return _loadCloudflareImage();
        },
      );
    } 
    
    // Try Cloudflare URL if local file doesn't exist
    return _loadCloudflareImage();
  }

  // Helper method to load image from Cloudflare
  Widget _loadCloudflareImage() {
    // First try cloudflare_url
    final cloudflareUrl = _videoDetails?['cloudflare_url'] as String?;
    if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
      print('Using Cloudflare URL for image: $cloudflareUrl');
      return Image.network(
        cloudflareUrl,
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
          // If cloudflare_url fails, try thumbnail_cloudflare_url
          final thumbnailUrl = _videoDetails?['thumbnail_cloudflare_url'] as String?;
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
              errorBuilder: (context, url, error) => Icon(
                Icons.image_not_supported,
                color: Colors.grey[400],
                size: 48,
              ),
            );
          }
          
          // If everything fails, show error icon
          return Icon(
            Icons.image_not_supported,
            color: Colors.grey[400],
            size: 48,
          );
        },
      );
    }
    
    // If no cloudflare_url, try thumbnail_cloudflare_url
    final thumbnailUrl = _videoDetails?['thumbnail_cloudflare_url'] as String?;
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      print('Using thumbnail Cloudflare URL for image: $thumbnailUrl');
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
        errorBuilder: (context, url, error) => Icon(
          Icons.image_not_supported,
          color: Colors.grey[400],
          size: 48,
        ),
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
    print('Getting loading thumbnail for draft details');
    
    // First try thumbnail_cloudflare_url
    final thumbnailUrl = _videoDetails?['thumbnail_cloudflare_url'] as String?;
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      print('Using thumbnail Cloudflare URL for loading: $thumbnailUrl');
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
          print('Failed to load thumbnail from Cloudflare: $error');
          return _getFallbackThumbnail();
        },
      );
    }
    
    // Then try local thumbnail_path
    final thumbnailPath = _videoDetails?['thumbnail_path'] as String?;
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      print('Using local thumbnail path for loading: $thumbnailPath');
      final thumbnailFile = File(thumbnailPath);
      if (thumbnailFile.existsSync()) {
        return Image.file(
          thumbnailFile,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            print('Failed to load local thumbnail: $error');
            return _getFallbackThumbnail();
          },
        );
      } else {
        print('Local thumbnail file does not exist: $thumbnailPath');
      }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaWidth = MediaQuery.of(context).size.width;
    final mediaHeight = MediaQuery.of(context).size.height;
    
    // Colore di sfondo più vivace ma velato per il video
    final videoBackgroundColor = Color(0xFF2C3E50).withOpacity(0.9); // Blu petrolio scuro e velato
    
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
        // Disable SafeArea when video is in fullscreen
        bottom: !_isFullScreen,
        top: !_isFullScreen,
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _isFullScreen
                // Simplified layout for fullscreen mode
                ? GestureDetector(
                    onTap: () {
                      setState(() {
                        _showControls = !_showControls;
                      });
                    },
                    child: Container(
                      width: mediaWidth,
                      height: mediaHeight,
                      color: videoBackgroundColor,
                      child: Stack(
                        children: [
                          // If the video is initialized, show it
                          if (_isVideoInitialized && _videoPlayerController != null)
                            Center(
                              child: _buildVideoPlayer(_videoPlayerController!),
                            ),
                          
                          // Video controls in fullscreen mode
                          AnimatedOpacity(
                            opacity: _showControls ? 1.0 : 0.0,
                            duration: Duration(milliseconds: 300),
                            child: Stack(
                              children: [
                                // Semi-transparent overlay
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
                                
                                // Exit fullscreen button
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
                                
                                // Play/Pause button in center
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
                                
                                // Progress bar
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
                  )
                // Normal layout with tab system
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Only show header when not in fullscreen
                      if (!_isFullScreen) _buildHeader(),
                      
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
                                      icon: Builder(
                                        builder: (context) {
                                          // Use _videoDetails if available, otherwise widget.video
                                          final videoDataToCheck = _videoDetails ?? widget.video;
                                          final cloudflareUrls = videoDataToCheck['cloudflare_urls'] as List<dynamic>?;
                                          final hasMultipleMedia = cloudflareUrls != null && cloudflareUrls.length > 1;
                                          return Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                hasMultipleMedia 
                                                    ? Icons.collections 
                                                    : (_isImage ? Icons.image : Icons.video_library), 
                                                size: 16
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                hasMultipleMedia 
                                                    ? 'Media' 
                                                    : (_isImage ? 'Image' : 'Video')
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                    Tab(
                                      icon: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.account_circle, size: 16),
                                          const SizedBox(width: 8),
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
                      
                      // Main content with PageView
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
                            // Prima sezione: Video
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.1, 0),
                                      end: Offset.zero,
                                    ).animate(CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeInOut,
                                    )),
                                    child: child,
                                  ),
                                );
                              },
                              child: _buildVideoSection(theme, mediaWidth, videoBackgroundColor),
                            ),
                            // Seconda sezione: Accounts
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.1, 0),
                                      end: Offset.zero,
                                    ).animate(CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeInOut,
                                    )),
                                    child: child,
                                  ),
                                );
                              },
                              child: _buildAccountsSection(theme),
                            ),
                          ],
                        ),
                      ),
                      
                      // Continue to Edit button fixed at bottom
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
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                              colors: [
                                Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                                Color(0xFF764ba2), // Colore finale: viola al 100%
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
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
                              // Use _videoDetails if available (contains all Firebase data including video_paths),
                              // otherwise fallback to widget.video
                              final draftDataToPass = _videoDetails ?? widget.video;
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UploadVideoPage(
                                    draftData: draftDataToPass,
                                    draftId: draftDataToPass['id'],
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'Continue to Edit',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
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
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 24,
                  ),
                ),
                onPressed: _showDeleteConfirmation,
                tooltip: 'Delete Draft',
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountsList(dynamic accounts, ThemeData theme) {
    try {
      final Map<String, List<Map<String, dynamic>>> platformsMap = {};
      
      // Process accounts data
      (accounts as Map).forEach((platform, platformAccounts) {
        if (platform is String && platformAccounts is List) {
          final processedAccounts = <Map<String, dynamic>>[];
          
          for (var account in platformAccounts) {
            if (account is Map) {
              final username = account['username']?.toString() ?? '';
              final accountId = account['id']?.toString() ??
                  account['channel_id']?.toString() ??
                  username;
              final customTitle = account['title']?.toString();
              final customDescription = account['description']?.toString();

              processedAccounts.add({
                'id': accountId,
                'username': username,
                'display_name': account['display_name']?.toString(),
                'profile_image_url': account['profile_image_url']?.toString(),
                'title': customTitle,
                'description': customDescription,
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
                    final customTitle = account['title']?.toString();
                    
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

  // Helper function to get platform colors
  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'twitter':
        return Colors.blue;
      case 'youtube':
        return Colors.red;
      case 'tiktok':
        return Colors.black;
      case 'instagram':
        return Colors.purple;
      case 'facebook':
        return Colors.blue.shade800;
      case 'threads':
        return Colors.black87;
      default:
        return Colors.grey;
    }
  }

  // Helper function to get light platform colors
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
        return Colors.blue.shade800.withOpacity(0.08);
      case 'threads':
        return Colors.black87.withOpacity(0.05);
      default:
        return Colors.grey.withOpacity(0.08);
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Delete Draft',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this draft?',
                style: TextStyle(
                  color: theme.textTheme.bodyMedium?.color,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This action cannot be undone.',
                style: TextStyle(
                  color: theme.textTheme.bodySmall?.color,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteDraft();
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteDraft() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Delete video file if exists
      final videoPath = widget.video['video_path'] as String?;
      if (videoPath != null) {
        final videoFile = File(videoPath);
        if (await videoFile.exists()) {
          await videoFile.delete();
        }
      }

      // Delete thumbnail if exists
      final thumbnailPath = widget.video['thumbnail_path'] as String?;
      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        final thumbnailFile = File(thumbnailPath);
        if (await thumbnailFile.exists()) {
          await thumbnailFile.delete();
        }
      }

      // Delete from Firebase
      await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .child(widget.video['id'])
          .remove();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Draft deleted successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.pop(context); // Return to previous screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Text('Error deleting draft: $e'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  // Funzione per mostrare la tendina con i dettagli del post
  void _showPostDetailsBottomSheet(BuildContext context, Map<String, dynamic> account, String platform) {
    final theme = Theme.of(context);
    final platformColor = (platform.toLowerCase() == 'threads' && theme.brightness == Brightness.dark)
        ? Colors.white
        : _getPlatformColor(platform);
    
    // Estrai i dati del post
    final username = account['username'] as String? ?? '';
    final displayName = account['display_name'] as String? ?? username;
    final profileImageUrl = account['profile_image_url'] as String?;
    final accountTitle = account['title']?.toString() ?? '';
    final accountDescription = account['description']?.toString() ?? '';
    final title = accountTitle.isNotEmpty
        ? accountTitle
        : widget.video['title'] as String? ?? '';
    final description = widget.video['description'] as String? ?? '';
    final resolvedDescription = accountDescription.isNotEmpty
        ? accountDescription
        : description;
    
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
            // Linea in alto per indicare che è trascinabile
            Center(
              child: Container(
                margin: EdgeInsets.only(top: 8, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
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
                    color: theme.dividerColor,
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
                    icon: Icon(Icons.close, color: theme.iconTheme.color),
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
                    color: theme.dividerColor,
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
                        backgroundColor: Colors.white,
                        backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                            ? NetworkImage(profileImageUrl)
                            : null,
                        child: profileImageUrl == null || profileImageUrl.isEmpty
                            ? Text(
                                username.isNotEmpty ? username[0].toUpperCase() : '',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
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
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Contenuto del post
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
                        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Text(
                          title.isNotEmpty ? title : 'No title available',
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
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Text(
                          resolvedDescription.isNotEmpty 
                              ? resolvedDescription 
                            : 'No description available',
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

  // Handle carousel page change
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
    
    // Reset controls
    setState(() {
      _showControls = true;
      _isPlaying = false;
    });
    
    // Initialize video player for current media if it's a video
    final videoDataToCheck = _videoDetails ?? widget.video;
    final cloudflareUrls = videoDataToCheck['cloudflare_urls'] as List<dynamic>?;
    if (cloudflareUrls != null && index < cloudflareUrls.length) {
      final mediaUrl = cloudflareUrls[index] as String?;
      if (mediaUrl != null) {
        // Check if it's a video (not an image)
        final isImage = mediaUrl.toLowerCase().contains('.jpg') || 
                       mediaUrl.toLowerCase().contains('.jpeg') || 
                       mediaUrl.toLowerCase().contains('.png') || 
                       mediaUrl.toLowerCase().contains('.gif') ||
                       mediaUrl.toLowerCase().contains('.webp') ||
                       mediaUrl.toLowerCase().contains('.bmp') ||
                       mediaUrl.toLowerCase().contains('.heic') ||
                       mediaUrl.toLowerCase().contains('.heif');
        
        if (!isImage) {
          // Initialize video player for this URL
          _currentVideoUrl = mediaUrl;
          _initializeNetworkVideoPlayer(mediaUrl);
        } else {
          // If it's an image, clear video URL
          _currentVideoUrl = null;
        }
      }
    }
  }
  
  // Build video player widget for network URL
  Widget _buildVideoPlayerWidget(String videoUrl, ThemeData theme, bool isFirstVideo) {
    // Show loading state while video is initializing or if URL doesn't match
    if (!_isVideoInitialized || 
        _videoPlayerController == null || 
        _currentVideoUrl != videoUrl) {
      // Show thumbnail while loading only for first video
      final thumbnailUrl = isFirstVideo 
          ? (_videoDetails?['thumbnail_cloudflare_url'] as String?) 
          : null;
      
      return Stack(
        fit: StackFit.expand,
        children: [
          // Show thumbnail if available (only for first video)
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
            Container(
              color: Colors.black,
            ),
          
          // Loading overlay
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
        // Video Player
        GestureDetector(
          onTap: () {
            setState(() {
              _showControls = !_showControls;
            });
          },
          child: _buildVideoPlayer(_videoPlayerController!),
        ),
        
        // Video Controls (same as single video)
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
  
  // Initialize network video player
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
      print('Initializing network video player for URL: $videoUrl');
      
      // Create network video controller
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );
      
      // Add listener for position updates
      _videoPlayerController!.addListener(_onVideoPositionChanged);
      
      // Initialize the controller
      await _videoPlayerController!.initialize();
      
      if (!mounted || _isDisposed) return;
      
      setState(() {
        _isVideoInitialized = true;
        _videoDuration = _videoPlayerController!.value.duration;
        _currentPosition = Duration.zero;
        _showControls = true;
        _currentVideoUrl = videoUrl; // Set current video URL
      });
      
      print('Network video player initialized successfully for URL: $videoUrl');
    } catch (e) {
      print('Error initializing network video player: $e');
      
      if (mounted && !_isDisposed) {
        setState(() {
          _isVideoInitialized = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to load video: ${e.toString().substring(0, min(e.toString().length, 50))}...'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Metodo per costruire la sezione video
  Widget _buildVideoSection(ThemeData theme, double mediaWidth, Color videoBackgroundColor) {
    // Check if we have cloudflare_urls - prioritize cloudflare_urls over cloudflare_url
    // Use carousel even if there's only 1 item in cloudflare_urls to avoid conflicts with cloudflare_url
    // Use _videoDetails if available, otherwise widget.video
    final videoDataToCheck = _videoDetails ?? widget.video;
    final cloudflareUrls = videoDataToCheck['cloudflare_urls'] as List<dynamic>?;
    final bool hasCloudflareUrls = cloudflareUrls != null && cloudflareUrls.isNotEmpty;
    final bool hasMultipleMedia = hasCloudflareUrls && cloudflareUrls!.length > 1;
    
    print('_buildVideoSection - videoDataToCheck keys: ${videoDataToCheck.keys.toList()}');
    print('_buildVideoSection - cloudflareUrls: $cloudflareUrls');
    print('_buildVideoSection - hasCloudflareUrls: $hasCloudflareUrls, hasMultipleMedia: $hasMultipleMedia');
    
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Video container a schermo intero
          Expanded(
            child: GestureDetector(
              onTap: () {
                print("Tap on video section container");
                if (!hasCloudflareUrls) {
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
                child: hasCloudflareUrls
                    ? _buildCarouselMediaPreview(theme)
                    : Stack(
                        children: [
                          // If it's an image, display it directly
                          if (_isImage)
                      Center(
                        child: _videoDetails?['video_path'] != null && 
                             _videoDetails!['video_path'].toString().isNotEmpty
                             ? _buildImagePreview(_videoDetails!['video_path'])
                             : _loadCloudflareImage(),
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
                                    
                                    // Pulsante Play/Pause al centro - sempre visibile quando il video è pronto
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
                    else if (_videoDetails?['thumbnail_cloudflare_url'] != null &&
                            _videoDetails!['thumbnail_cloudflare_url'].toString().isNotEmpty)
                      Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.black,
                        child: Center(
                          child: Image.network(
                            _videoDetails!['thumbnail_cloudflare_url'],
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
                    // Or show local thumbnail if available
                    else if (_videoDetails?['thumbnail_path'] != null &&
                            _videoDetails!['thumbnail_path'].toString().isNotEmpty)
                      Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.black,
                        child: Center(
                          child: Image.file(
                            File(_videoDetails!['thumbnail_path']),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Center(
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

  // Build carousel media preview
  Widget _buildCarouselMediaPreview(ThemeData theme) {
    // Get media URLs directly from _videoDetails or widget if _mediaUrls is empty (async loading)
    // Use _videoDetails if available, otherwise widget.video
    final videoDataToCheck = _videoDetails ?? widget.video;
    final cloudflareUrls = videoDataToCheck['cloudflare_urls'] as List<dynamic>?;
    final mediaUrlsToUse = _mediaUrls.isNotEmpty 
        ? _mediaUrls 
        : (cloudflareUrls != null ? cloudflareUrls.cast<String>() : <String>[]);
    
    print('_buildCarouselMediaPreview - mediaUrlsToUse.length: ${mediaUrlsToUse.length}');
    print('_buildCarouselMediaPreview - _carouselController: ${_carouselController != null}');
    
    // Get image list directly or compute it
    List<bool> isImageListToUse;
    if (_isImageList.length == mediaUrlsToUse.length && _isImageList.isNotEmpty) {
      isImageListToUse = _isImageList;
    } else {
      // Compute on the fly
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
      print('Created carousel controller on-the-fly');
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
              // For videos, use VideoPlayerController.networkUrl for remote video URLs
              // Only initialize video player for current carousel index to save memory
              if (index == _currentCarouselIndex) {
                // Initialize video player for current video
                return _buildVideoPlayerWidget(mediaUrl, theme, index == 0);
              } else {
                // For non-current videos, show placeholder or thumbnail
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
      ],
    );
  }

  // Metodo per costruire la sezione accounts
  Widget _buildAccountsSection(ThemeData theme) {
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
            // Social Media Section
            if (widget.video['accounts'] != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: _buildAccountsList(widget.video['accounts'], theme),
              ),
          ],
        ),
      ),
    );
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
      'id': account['id']?.toString() ?? account['username']?.toString() ?? '',
      'channel_id': account['id']?.toString() ?? account['username']?.toString() ?? '',
      'user_id': account['id']?.toString() ?? account['username']?.toString() ?? '',
      'followersCount': '0', // Default value since we don't have this info in draft
      'bio': '', // Default empty bio since we don't have this info in draft
      'location': '', // Default empty location since we don't have this info in draft
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

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
} 