import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../social/social_account_details_page.dart';
import '../../pages/settings_page.dart';
import '../../pages/profile_page.dart';
import 'dart:math';

class YouTubePage extends StatefulWidget {
  const YouTubePage({super.key});

  @override
  State<YouTubePage> createState() => _YouTubePageState();
}

class _YouTubePageState extends State<YouTubePage> with TickerProviderStateMixin {
  // Firebase configuration
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  
  // YouTube API configuration
  late final GoogleSignIn _googleSignIn;
  
  // State variables
  bool _isLoading = true;
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _inactiveAccounts = [];
  late TabController _tabController;
  bool _showInfo = false;
  User? _currentUser;
  
  // Animation controller for info section
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  // Video player for tutorial
  VideoPlayerController? _tutorialVideoController;
  bool _isTutorialVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    
    // Initialize tab controller
    _tabController = TabController(length: 2, vsync: this);
    
    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    
    _initializeServices();
    _loadAccounts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    _tutorialVideoController?.dispose();
    super.dispose();
  }
  
  // Initialize tutorial video
  Future<void> _initializeTutorialVideo() async {
    try {
      print('Initializing YouTube tutorial video...');
      _tutorialVideoController = VideoPlayerController.asset('assets/animations/tutorial/youtube.mp4');
      await _tutorialVideoController!.initialize();
      _tutorialVideoController!.setLooping(true);
      _tutorialVideoController!.setVolume(0.0); // Mute per il tutorial
      print('YouTube tutorial video initialized successfully');
      print('Video duration: ${_tutorialVideoController!.value.duration}');
      print('Video size: ${_tutorialVideoController!.value.size}');
      _tutorialVideoController!.addListener(() {
        if (mounted) {
          setState(() {
            // Forza il rebuild per aggiornare l'UI del video
          });
        }
      });
      setState(() {
        _isTutorialVideoInitialized = true;
      });
    } catch (e) {
      print('Error initializing tutorial video: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }
  
  // Show video in fullscreen - stesso design di TikTok
  void _showVideoFullscreen() {
    if (_tutorialVideoController != null && _isTutorialVideoInitialized) {
      // Avvia il video quando si apre il fullscreen
      _tutorialVideoController!.play();
      
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            color: Colors.black,
            child: Stack(
              children: [
                // Video fullscreen con design copiato da TikTok
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85, // Ridotto da 0.90 a 0.85 (circa 1cm in meno)
                    margin: const EdgeInsets.only(top: 24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.black,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: AspectRatio(
                        aspectRatio: 8 / 16, // Cambiato da 9:16 a 8:16 per video più stretto
                        child: VideoPlayer(_tutorialVideoController!),
                      ),
                    ),
                  ),
                ),
                
                // Overlay per il tap play/pause - identico a TikTok
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    child: AspectRatio(
                      aspectRatio: 8 / 16,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          if (_tutorialVideoController == null) return;
                          if (_tutorialVideoController!.value.isPlaying) {
                            await _tutorialVideoController!.pause();
                          } else {
                            await _tutorialVideoController!.play();
                          }
                          if (mounted) setState(() {});
                        },
                        onDoubleTap: () async {
                          // restart quickly on double tap
                          if (_tutorialVideoController == null) return;
                          await _tutorialVideoController!.seekTo(Duration.zero);
                          await _tutorialVideoController!.play();
                        },
                        child: AnimatedOpacity(
                          opacity: _tutorialVideoController!.value.isPlaying ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            color: Colors.black26,
                            child: const Icon(
                              Icons.play_arrow,
                              size: 60,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Close button
                Positioned(
                  top: 40,
                  left: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                
                // Bottom progress bar (seconds) - stesso design di TikTok
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: _tutorialVideoController!,
                    builder: (context, value, child) {
                      final currentMs = value.position.inMilliseconds.toDouble();
                      final durationMs = (value.duration?.inMilliseconds.toDouble() ?? 1.0);
                      final max = durationMs > 0 ? durationMs : 1.0;
                      final clamped = currentMs.clamp(0.0, max);
                      
                      // Converti millisecondi in formato mm:ss
                      final currentMinutes = (currentMs / 60000).floor();
                      final currentSeconds = ((currentMs % 60000) / 1000).floor();
                      final totalMinutes = (durationMs / 60000).floor();
                      final totalSeconds = ((durationMs % 60000) / 1000).floor();
                      
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            // Progress bar migliorata con area di cliccaggio più ampia
                            Container(
                              height: 30,
                              child: Row(
                                children: [
                                  // Minutaggio corrente (sinistra)
                                  Text(
                                    '${currentMinutes.toString().padLeft(2, '0')}:${currentSeconds.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withOpacity(0.8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  // Progress bar al centro con Expanded
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderThemeData(
                                        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 0),
                                        trackHeight: 8,
                                        activeTrackColor: Colors.white,
                                        inactiveTrackColor: Colors.white.withOpacity(0.3),
                                        thumbColor: Colors.transparent,
                                        overlayColor: Colors.transparent,
                                        trackShape: RoundedRectSliderTrackShape(),
                                      ),
                                      child: Slider(
                                        value: clamped,
                                        min: 0.0,
                                        max: max,
                                        onChanged: (v) {
                                          _tutorialVideoController?.seekTo(Duration(milliseconds: v.toInt()));
                                        },
                                        onChangeEnd: (_) {},
                                        onChangeStart: (_) {},
                                      ),
                                    ),
                                  ),
                                  // Minutaggio totale (destra)
                                  Text(
                                    '${totalMinutes.toString().padLeft(2, '0')}:${totalSeconds.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withOpacity(0.8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ).whenComplete(() {
        // Ferma il video quando si chiude il fullscreen
        if (_tutorialVideoController != null && _isTutorialVideoInitialized) {
          _tutorialVideoController!.pause();
          _tutorialVideoController!.seekTo(Duration.zero);
        }
      });
    }
  }

  void _initializeServices() {
    // Initialize Firebase
    FirebaseDatabase.instance.databaseURL = 'https://viralyst-giusta-default-rtdb.europe-west1.firebasedatabase.app';

    // Initialize Google Sign-In based on platform
    if (Platform.isIOS) {
      _googleSignIn = GoogleSignIn(
        scopes: [
          'https://www.googleapis.com/auth/youtube.upload',
          'https://www.googleapis.com/auth/youtube.readonly',
          'https://www.googleapis.com/auth/youtube',
          'https://www.googleapis.com/auth/youtube.force-ssl'
        ],
        clientId: '1095391771291-ner3467g5fqv14j0l5886qe5u7sho8a2.apps.googleusercontent.com',
        signInOption: SignInOption.standard,
      );
    } else if (Platform.isAndroid) {
      _googleSignIn = GoogleSignIn(
        scopes: [
          'https://www.googleapis.com/auth/youtube.upload',
          'https://www.googleapis.com/auth/youtube.readonly',
          'https://www.googleapis.com/auth/youtube',
          'https://www.googleapis.com/auth/youtube.force-ssl'
        ],
        serverClientId: '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com',
        clientId: '1095391771291-8kt5sjfe26rftvmr3o8pnpmj9v4iv7u4.apps.googleusercontent.com',
        signInOption: SignInOption.standard,
      );
    } else {
      _googleSignIn = GoogleSignIn(
        scopes: [
          'https://www.googleapis.com/auth/youtube.upload',
          'https://www.googleapis.com/auth/youtube.readonly',
          'https://www.googleapis.com/auth/youtube',
          'https://www.googleapis.com/auth/youtube.force-ssl'
        ],
        clientId: '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com',
        signInOption: SignInOption.standard,
      );
    }
  }

  Future<void> _loadAccounts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final snapshot = await _database.child('users/${user.uid}/youtube').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final allAccounts = data.entries.map((entry) => {
          'id': entry.key,
          'channel_name': entry.value['channel_name'] ?? '',
          'channel_id': entry.value['channel_id'] ?? '',
          'subscriber_count': entry.value['subscriber_count'] ?? 0,
          'last_sync': entry.value['last_sync'] ?? 0,
          'status': entry.value['status'] ?? 'active',
          'thumbnail_url': entry.value['thumbnail_url'] ?? '',
          'video_count': entry.value['video_count'] ?? 0,
          'is_verified': entry.value['is_verified'] ?? false,
        }).toList();
        
        setState(() {
          _accounts = allAccounts.where((account) => account['status'] == 'active').toList();
          _inactiveAccounts = allAccounts.where((account) => account['status'] == 'inactive').toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _accounts = [];
          _inactiveAccounts = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading accounts: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _getYouTubeChannels(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://www.googleapis.com/youtube/v3/channels?part=snippet,statistics,status&mine=true'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('YouTube API Response: ${json.encode(data)}'); // Debug completo della risposta
        
        if (data['items'] != null && data['items'].isNotEmpty) {
          return List<Map<String, dynamic>>.from(data['items'].map((channel) {
            print('Channel data: ${json.encode(channel)}'); // Debug per ogni canale
            print('Snippet data: ${json.encode(channel['snippet'])}'); // Debug del snippet
            print('Status data: ${json.encode(channel['status'])}'); // Debug del status
            
            // Controlla la verifica del telefono tramite longUploadsStatus
            String longUploadsStatus = channel['status']?['longUploadsStatus'] ?? 'disallowed';
            bool isPhoneVerified = longUploadsStatus == 'allowed';
            
            print('Phone verification details for ${channel['id']}:');
            print('  - Long uploads status: $longUploadsStatus');
            print('  - Phone verified: $isPhoneVerified');
            print('  - Status object: ${json.encode(channel['status'])}');
            
            return {
              'id': channel['id'],
              'title': channel['snippet']['title'],
              'description': channel['snippet']['description'],
              'thumbnailUrl': channel['snippet']['thumbnails']['default']['url'],
              'subscriberCount': int.tryParse(channel['statistics']['subscriberCount'] ?? '0') ?? 0,
              'videoCount': int.tryParse(channel['statistics']['videoCount'] ?? '0') ?? 0,
              'isVerified': isPhoneVerified,
            };
          }));
        }
      }
      print('YouTube API Error: ${response.body}');
      return [];
    } catch (e) {
      print('Error getting YouTube channels: $e');
      return [];
    }
  }

  Future<void> _showChannelSelectionDialog(String accessToken) async {
    final channels = await _getYouTubeChannels(accessToken);
    if (!mounted) return;

    if (channels.isEmpty) {
      return;
    }

    final selectedChannel = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9, // Almost full width
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset(
                        'assets/loghi/logo_yt.png',
                        width: 24,
                        height: 24,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Channel',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Close button
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey[500]),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(),
                      splashRadius: 24,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: Colors.grey[200]),
              Flexible(
                child: ListView.separated(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shrinkWrap: true,
                  itemCount: channels.length,
                  separatorBuilder: (context, index) => Divider(height: 1, indent: 90, endIndent: 24),
                  itemBuilder: (context, index) {
                    final channel = channels[index];
                    return ListTile(
                      contentPadding: EdgeInsets.fromLTRB(24, 8, 24, 8),
                      leading: CircleAvatar(
                        radius: 26,
                        backgroundImage: NetworkImage(channel['thumbnailUrl']),
                        backgroundColor: Colors.red.withOpacity(0.1),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              channel['title'],
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          // RIMOSSO BADGE PHONE VERIFIED
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              SizedBox(width: 4),
                              Text(
                                '${channel['subscriberCount']} subscribers',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.video_library_outlined,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              SizedBox(width: 4),
                              Text(
                                '${channel['videoCount']} videos',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Container(
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.add,
                          size: 16,
                          color: Colors.red,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(channel),
                    );
                  },
                ),
              ),
              Divider(height: 1, thickness: 1, color: Colors.grey[200]),
              Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'Tap on a channel to connect it to Fluzar',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedChannel != null) {
      await _connectChannel(selectedChannel);
    }
  }

  Future<void> _connectChannel(Map<String, dynamic> channel) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _database.child('users/${user.uid}/youtube/${channel['id']}').set({
        'channel_name': channel['title'],
        'channel_id': channel['id'],
        'subscriber_count': channel['subscriberCount'],
        'last_sync': DateTime.now().millisecondsSinceEpoch,
        'thumbnail_url': channel['thumbnailUrl'],
        'video_count': channel['videoCount'],
        'is_verified': channel['isVerified'] ?? false,
        'status': 'active',
      });

      await _loadAccounts();

    } catch (e) {
      print('Error connecting channel: $e');
    }
  }

  Future<void> _connectYouTubeAccount() async {
    try {
      setState(() => _isLoading = true);

      // Sign out from any previous session
      await _googleSignIn.signOut();
      
      // Sign in with Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Get authentication details
      try {
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        if (googleAuth.accessToken == null) {
          throw Exception('Failed to get access token');
        }
        
        // Show channel selection dialog
        await _showChannelSelectionDialog(googleAuth.accessToken!);
      } catch (authError) {
        print('Authentication error: $authError');
        await _googleSignIn.signOut();
      }

    } catch (e) {
      print('Error connecting YouTube account: $e');
      if (e.toString().contains('ApiException: 10')) {
        String errorMessage = '''Please follow these steps to fix the YouTube connection:
1. Go to Google Cloud Console (https://console.cloud.google.com)
2. Select project "Viralyst Giusta"
3. Go to "APIs & Services" > "Enabled APIs & Services"
4. Click "+ ENABLE APIS AND SERVICES"
5. Search for "YouTube Data API v3" and enable it
6. Go to "OAuth consent screen" and verify the configuration
7. Make sure the following scopes are added to your OAuth consent screen:
   - https://www.googleapis.com/auth/youtube.upload
   - https://www.googleapis.com/auth/youtube.readonly
   - https://www.googleapis.com/auth/youtube
   - https://www.googleapis.com/auth/youtube.force-ssl
8. Save the changes and wait a few minutes for them to take effect
9. Verify that the API key is enabled for the YouTube Data API v3
10. Make sure the OAuth consent screen is in "Testing" or "Production" mode
11. Add your email (jacopoberto19@gmail.com) to the test users list if in testing mode''';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 15),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removeAccount(String accountId) async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _database.child('users/${user.uid}/youtube/$accountId').update({
        'status': 'inactive',
      });

      await _loadAccounts();

    } catch (e) {
      print('Error removing account: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _reactivateAccount(String accountId) async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _database.child('users/${user.uid}/youtube/$accountId').update({
        'status': 'active',
      });

      await _loadAccounts();

    } catch (e) {
      print('Error reactivating account: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark ? Colors.grey[900]! : Colors.grey[50]!,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            // Introduction section
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Colors.grey[850]! : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: theme.brightness == Brightness.dark 
                        ? Colors.black.withOpacity(0.3)
                        : Colors.black.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.brightness == Brightness.dark 
                                  ? Colors.red.withOpacity(0.2)
                                  : Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Image.asset(
                              'assets/loghi/logo_yt.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'YouTube Channels',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: AnimatedIcon(
                          icon: AnimatedIcons.menu_close,
                          progress: _animation,
                          color: Colors.red,
                        ),
                        onPressed: () {
                          setState(() {
                            _showInfo = !_showInfo;
                            if (_showInfo) {
                              _animationController.forward();
                            } else {
                              _animationController.reverse();
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  SizeTransition(
                    sizeFactor: _animation,
                    child: FadeTransition(
                      opacity: _animation,
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          _buildInfoItem(
                            'Channel Management',
                            'Manage your YouTube channels and track their performance.',
                            Icons.account_box,
                          ),
                          _buildInfoItem(
                            'Interactive Details',
                            'Click on any channel to view the videos published with Fluzar.',
                            Icons.touch_app,
                          ),
                          _buildInfoItem(
                            'Account Visibility',
                            'Deactivated channels won\'t appear in video upload selection.',
                            Icons.visibility_off,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Improved tab bar - more compact and elegant
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Container(
                height: 36, // Reduced height
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark ? Colors.grey[850]! : Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: theme.brightness == Brightness.dark 
                          ? Colors.black.withOpacity(0.3)
                          : Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[500],
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: LinearGradient(
                        colors: [
                          Colors.red,
                          Colors.red.shade700,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12, // Smaller font
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 12, // Smaller font
                    ),
                    labelPadding: EdgeInsets.zero,
                    padding: EdgeInsets.zero,
                    tabs: const [
                      Tab(text: 'Active Channels'),
                      Tab(text: 'Inactive Channels'),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        // Active Accounts Tab
                        _accounts.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: theme.brightness == Brightness.dark 
                                            ? Colors.red.withOpacity(0.2)
                                            : Colors.red.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Image.asset(
                                        'assets/loghi/logo_yt.png',
                                        width: 64,
                                        height: 64,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      'No Active YouTube Channels',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 32),
                                      child: Text(
                                        'Connect your YouTube channel or reactivate it',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _accounts.length,
                                itemBuilder: (context, index) {
                                  final account = _accounts[index];
                                  return _buildAccountCard(account, isActive: true);
                                },
                              ),
                        // Inactive Accounts Tab
                        _inactiveAccounts.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: theme.brightness == Brightness.dark 
                                            ? Colors.red.withOpacity(0.2)
                                            : Colors.red.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Image.asset(
                                        'assets/loghi/logo_yt.png',
                                        width: 64,
                                        height: 64,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      'No Inactive YouTube Channels',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 32),
                                      child: Text(
                                        'Connect your YouTube channel or reactivate it',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _inactiveAccounts.length,
                                itemBuilder: (context, index) {
                                  final account = _inactiveAccounts[index];
                                  return _buildAccountCard(account, isActive: false);
                                },
                              ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _connectYouTubeAccount,
        heroTag: 'youtube_fab',
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Connect YouTube Channel'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? Colors.grey[850]! : Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.brightness == Brightness.dark 
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_back_ios,
                      color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return LinearGradient(
                          colors: [
                            Colors.red.shade600,
                            Colors.red.shade800,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds);
                      },
                      child: const Text(
                        'YouTube',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark 
                      ? Colors.red.withOpacity(0.2)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: theme.brightness == Brightness.dark 
                        ? Colors.red.withOpacity(0.4)
                        : Colors.red.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.smart_display,
                      size: 14,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Channels',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String title, String description, IconData icon) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark 
                  ? Colors.red.withOpacity(0.2)
                  : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: Colors.red,
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
                    color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(Map<String, dynamic> account, {required bool isActive}) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: theme.brightness == Brightness.dark ? Colors.grey[850]! : Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.brightness == Brightness.dark ? Colors.grey[850]! : Colors.white,
          boxShadow: [
            BoxShadow(
              color: theme.brightness == Brightness.dark 
                  ? Colors.black.withOpacity(0.3)
                  : Colors.black.withOpacity(0.05),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SocialAccountDetailsPage(
                  account: {
                    'id': account['channel_id'],
                    'username': account['channel_name'],
                    'displayName': account['channel_name'],
                    'profileImageUrl': account['thumbnail_url'],
                    'followersCount': account['subscriber_count'],
                    'description': 'YouTube Channel',
                    'isVerified': account['is_verified'] ?? false,
                  },
                  platform: 'youtube',
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        if (account['thumbnail_url']?.isNotEmpty ?? false)
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              image: DecorationImage(
                                image: NetworkImage(account['thumbnail_url']),
                                fit: BoxFit.cover,
                              ),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.2),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.1),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.red.withOpacity(0.2),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.smart_display,
                              size: 32,
                              color: Colors.red,
                            ),
                          ),
                        // Status indicator
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: isActive ? Colors.green : Colors.grey,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.brightness == Brightness.dark ? Colors.grey[850]! : Colors.white,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Icon(
                              isActive ? Icons.check : Icons.close,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account['channel_name'],
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 14,
                                color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${account['subscriber_count']} subscribers',
                                style: TextStyle(
                                  color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Creation date
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 14,
                                color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Connected ${_formatDate(account['last_sync'])}',
                                style: TextStyle(
                                  color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Action button
                    isActive ? 
                    IconButton(
                      icon: Icon(
                        Icons.remove_circle_outline,
                        color: Colors.red,
                        size: 22,
                      ),
                      tooltip: 'Deactivate Channel',
                      onPressed: () => _removeAccount(account['id']),
                    ) :
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade700,
                        size: 22,
                      ),
                      tooltip: 'Delete Account',
                      onPressed: () => _showDeleteConfirmationDialog(account),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                Divider(height: 1, color: theme.brightness == Brightness.dark ? Colors.grey[700] : Colors.grey.withOpacity(0.15)),
                const SizedBox(height: 12),
                
                // Bottom actions row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive 
                            ? (theme.brightness == Brightness.dark ? Colors.green.withOpacity(0.2) : Colors.green.withOpacity(0.1))
                            : (theme.brightness == Brightness.dark ? Colors.grey.withOpacity(0.2) : Colors.grey.withOpacity(0.1)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isActive 
                              ? (theme.brightness == Brightness.dark ? Colors.green.withOpacity(0.4) : Colors.green.withOpacity(0.2))
                              : (theme.brightness == Brightness.dark ? Colors.grey.withOpacity(0.4) : Colors.grey.withOpacity(0.2)),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isActive ? Icons.check_circle_outline : Icons.cancel_outlined,
                            size: 12,
                            color: isActive ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isActive ? 'ACTIVE' : 'INACTIVE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isActive ? Colors.green : Colors.grey,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Badge per account non verificati
                    if (isActive && account['is_verified'] == false)
                      GestureDetector(
                        onTap: () => _showPhoneVerificationPrompt(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.phone_android,
                                size: 12,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'VERIFY PHONE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    // Action button
                    if (!isActive)
                      OutlinedButton.icon(
                        onPressed: () => _reactivateAccount(account['id']),
                        icon: Icon(Icons.refresh, size: 16, color: Colors.green),
                        label: Text(
                          'Reactivate',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          minimumSize: Size(0, 32),
                          side: BorderSide(color: Colors.green.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
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
    );
  }

  // Add this method to show the phone verification prompt
  void _showPhoneVerificationPrompt() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          child: Container(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.phone_android,
                        size: 24,
                        color: Colors.red,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: Colors.grey[600]),
                    ),
                  ],
                ),
                
                SizedBox(height: 16),
                
                // Title
                Text(
                  'Phone Verification Required',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                
                SizedBox(height: 8),
                
                // Subtitle
                Text(
                  'To upload videos longer than 15 minutes and use custom thumbnails, you need to verify your phone number with YouTube.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                SizedBox(height: 16),
                
                // Info box
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.red,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This verification is required by YouTube',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 24),
                
                // See how tutorial link - semplice e poco ingombrante
                GestureDetector(
                  onTap: () async {
                    // Inizializza il video se non è già inizializzato
                    if (!_isTutorialVideoInitialized) {
                      await _initializeTutorialVideo();
                    }
                    // Mostra il video in fullscreen solo se è inizializzato
                    if (_isTutorialVideoInitialized) {
                      _showVideoFullscreen();
                    }
                  },
                  child: Text(
                    'See how',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                
                SizedBox(height: 24),
                
                // Action buttons
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _openYouTubeVerification();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Verify Now',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _reconnectYouTubeAccount();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Reconnect Account',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Reconnect only after completing phone verification',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Method to open YouTube verification page
  void _openYouTubeVerification() async {
    try {
      final url = 'https://www.youtube.com/verify';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open YouTube verification page'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Error opening YouTube verification: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening verification page'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Method to reconnect YouTube account after verification
  void _reconnectYouTubeAccount() async {
    try {
      setState(() => _isLoading = true);
      
      // Sign out from current Google account
      await _googleSignIn.signOut();

      // Start new authentication process
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser != null) {
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final accessToken = googleAuth.accessToken;
        
        if (accessToken != null) {
          // Get updated channel information
          final channels = await _getYouTubeChannels(accessToken);
          
          if (channels.isNotEmpty) {
            // Update the account with new verification status
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              for (final channel in channels) {
                await _database
                    .child('users/${user.uid}/youtube/${channel['id']}')
                    .update({
                  'is_verified': channel['isVerified'],
                  'last_sync': DateTime.now().millisecondsSinceEpoch,
                });
              }
            }
            
            // Reload accounts to show updated status
            await _loadAccounts();
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('No YouTube channels found'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to get access token'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        // Authentication cancelled - no action needed
      }
    } catch (e) {
      print('Error reconnecting YouTube account: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reconnecting account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Add this method to show the confirmation dialog
  void _showDeleteConfirmationDialog(Map<String, dynamic> account) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.warning_amber_rounded, 
                color: Colors.red.shade600,
                size: 24,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Remove Account',
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
            Text(
              'Are you sure you want to completely remove the channel "${account['channel_name']}" from your Fluzar account?',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Colors.blue,
                  ),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'This will only remove the channel from Fluzar. Your YouTube channel will not be affected.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
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
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _permanentlyRemoveAccount(account['id']);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text('Remove'),
          ),
        ],
      ),
    );
  }

  // Add this method to permanently remove the account from database
  Future<void> _permanentlyRemoveAccount(String accountId) async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Remove the account from the database
      await _database.child('users/${user.uid}/youtube/$accountId').remove();

      // Refresh the UI
      await _loadAccounts();

    } catch (e) {
      print('Error removing account: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatDate(int timestamp) {
    if (timestamp == 0) return 'recently';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}/${date.month}/${date.year}';
  }
}
