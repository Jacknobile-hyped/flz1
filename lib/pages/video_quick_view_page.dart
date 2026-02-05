import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' show pi;
import 'dart:convert' show jsonEncode;
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'package:viralyst/pages/profile_edit_page.dart'; // Added import for ProfileEditPage

class VideoQuickViewPage extends StatefulWidget {
  final String videoId;
  final String videoOwnerId;
  final bool openComments;
  final String? highlightCommentId;
  final bool openStars;
  final String? highlightStarUserId;
  // New: open replies directly and highlight a specific reply under a parent comment
  final bool openReplies;
  final String? parentCommentIdForReplies;
  final String? highlightReplyId;

  const VideoQuickViewPage({
    super.key,
    required this.videoId,
    required this.videoOwnerId,
    this.openComments = false,
    this.highlightCommentId,
    this.openStars = false,
    this.highlightStarUserId,
    // New optional params
    this.openReplies = false,
    this.parentCommentIdForReplies,
    this.highlightReplyId,
  });

  @override
  State<VideoQuickViewPage> createState() => _VideoQuickViewPageState();
}

class _VideoQuickViewPageState extends State<VideoQuickViewPage> with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  Map<String, dynamic>? _videoData;
  bool _isLoading = true;
  String? _errorMessage;

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isProgressInteracting = false;

  // Animazioni per stelle commenti/replies (riuso pattern di community_page)
  final Map<String, AnimationController> _commentStarAnimationControllers = {};
  final Map<String, Animation<double>> _commentStarScaleAnimations = {};
  final Map<String, Animation<double>> _commentStarRotationAnimations = {};

  // Cache conteggio commenti
  Map<String, int> _commentsCountCache = {};
  
  // Debounce per prevenire doppi tap (fix iOS)
  Map<String, DateTime> _lastStarTapTime = {};
  static const Duration _starDebounceTime = Duration(milliseconds: 500);
  
  // Immagine profilo utente corrente
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    _loadVideo();
    _loadProfileImage();
    // Auto open comments, stars or replies if requested
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.openComments == true) {
        _showCommentsSheet();
      }
      if (widget.openStars == true) {
        _showStarredUsersSheetQuick();
      }
      if (widget.openReplies == true && widget.parentCommentIdForReplies != null) {
        _openRepliesForParent(widget.parentCommentIdForReplies!, widget.highlightReplyId);
      }
    });
  }

  Future<void> _loadVideo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final snap = await _database
          .child('users')
          .child('users')
          .child(widget.videoOwnerId)
          .child('videos')
          .child(widget.videoId)
          .get();

      if (!snap.exists || snap.value is! Map) {
        setState(() {
          _errorMessage = 'Video not found';
          _isLoading = false;
        });
        return;
      }

      final raw = Map<String, dynamic>.from(snap.value as Map);
      // Costruisci URL di riproduzione con priorità: media_url -> cloudflare_url -> video_path (http)
      final mediaUrl = (raw['media_url'] as String?)?.trim();
      final cloudflareUrl = (raw['cloudflare_url'] as String?)?.trim();
      final videoPath = (raw['video_path'] as String?)?.trim();

      String? playbackUrl;
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        playbackUrl = mediaUrl;
      } else if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
        playbackUrl = cloudflareUrl;
      } else if (videoPath != null && videoPath.isNotEmpty &&
          (videoPath.startsWith('http://') || videoPath.startsWith('https://'))) {
        playbackUrl = videoPath;
      }

      if (playbackUrl == null) {
        setState(() {
          _errorMessage = 'Video source not available';
          _isLoading = false;
        });
        return;
      }

      _videoData = raw;
      await _initializeController(playbackUrl);
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore nel caricamento del video';
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeController(String url) async {
    try {
      _disposeController();
      _controller = VideoPlayerController.network(url);
      
      // Fix iOS: Aggiungi timeout per l'inizializzazione
      await _controller!.initialize().timeout(
        Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Video initialization timeout');
        },
      );
      
      // Loop video alla fine
      _controller!.setLooping(true);
      
      // Fix iOS: Controlla che il controller sia ancora valido
      if (!mounted || _controller == null) return;
      
      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });
      
      _controller!.addListener(() {
        if (!mounted || _controller == null) return;
        
        final isPlaying = _controller!.value.isPlaying;
        if (isPlaying != _isPlaying && mounted) {
          setState(() {
            _isPlaying = isPlaying;
          });
        }
        
        // Safety: if reaches end and somehow stops, restart (fix iOS)
        if (_controller!.value.position >= _controller!.value.duration && 
            !_controller!.value.isPlaying && 
            _controller!.value.isInitialized) {
          _controller!.seekTo(Duration.zero);
          _controller!.play();
        }
      });
      
      // Fix iOS: Verifica che il controller sia ancora inizializzato prima di riprodurre
      if (_controller != null && _controller!.value.isInitialized && mounted) {
        await _controller!.play();
        if (mounted) {
          setState(() {
            _isPlaying = true;
          });
        }
      }
    } catch (e) {
      print('Error initializing video controller: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error in loading the media';
          _isLoading = false;
        });
      }
    }
  }

  void _disposeController() {
    try {
      // Fix iOS: Pausa il video prima di disporre del controller
      if (_controller != null && _controller!.value.isInitialized) {
        if (_controller!.value.isPlaying) {
          _controller!.pause();
        }
        _controller!.dispose();
      }
    } catch (e) {
      print('Error disposing video controller: $e');
    }
    _controller = null;
    _isInitialized = false;
    _isPlaying = false;
  }

  Future<void> _loadProfileImage() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
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

  // Carica l'immagine profilo dell'utente da Firebase
  Future<String?> _loadUserProfileImage(String userId) async {
    try {
      final snapshot = await _database
          .child('users')
          .child('users')
          .child(userId)
          .child('profile')
          .child('profileImageUrl')
          .get();
      
      if (snapshot.exists && snapshot.value is String) {
        return snapshot.value as String;
      }
      return null;
    } catch (e) {
      print('Error loading user profile image for $userId: $e');
      return null;
    }
  }

  Future<int> _getCommentsCount(String videoId, String videoOwnerId) async {
    final cacheKey = '${videoOwnerId}_$videoId';
    if (_commentsCountCache.containsKey(cacheKey)) {
      return _commentsCountCache[cacheKey]!;
    }
    try {
      final commentsSnapshot = await _database
          .child('users')
          .child('users')
          .child(videoOwnerId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .get();
      int commentCount = 0;
      if (commentsSnapshot.exists) {
        final dynamic raw = commentsSnapshot.value;
        if (raw is Map) {
          commentCount = raw.length;
        } else if (raw is List) {
          commentCount = raw.where((e) => e != null).length;
        }
      }
      _commentsCountCache[cacheKey] = commentCount;
      return commentCount;
    } catch (e) {
      return 0;
    }
  }

  Future<void> _submitComment(String videoId, String videoUserId, String commentText, Map<String, dynamic> video) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    try {
      final currentUserId = currentUser.uid;
      final currentUserDisplayName = currentUser.displayName ?? 'Anonymous';
      final currentUserProfileImage = _profileImageUrl ?? currentUser.photoURL;
      final commentId = DateTime.now().millisecondsSinceEpoch.toString();

      final commentRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(commentId);

      final commentData = {
        'id': commentId,
        'text': commentText,
        'userId': currentUserId,
        'userDisplayName': currentUserDisplayName,
        'userProfileImage': currentUserProfileImage,
        'timestamp': ServerValue.timestamp,
        'videoId': videoId,
        'replies_count': 0,
        'star_count': 0,
        'star_users': {},
      };
      await commentRef.set(commentData);

      if (currentUserId != videoUserId) {
        final notificationCommentRef = _database
            .child('users')
            .child('users')
            .child(videoUserId)
            .child('notificationcomment')
            .child(commentId);
        final notificationCommentData = {
          'id': commentId,
          'text': commentText,
          'userId': currentUserId,
          'userDisplayName': currentUserDisplayName,
          'userProfileImage': currentUserProfileImage,
          'timestamp': ServerValue.timestamp,
          'videoId': videoId,
          'videoTitle': video['title'] ?? 'Untitled Video',
          'videoOwnerId': videoUserId,
          'type': 'comment',
          'read': false,
          'replies_count': 0,
          'star_count': 0,
          'star_users': {},
        };
        await notificationCommentRef.set(notificationCommentData);
      }

      final cacheKey = '${videoUserId}_$videoId';
      final currentCount = _commentsCountCache[cacheKey] ?? 0;
      _commentsCountCache[cacheKey] = currentCount + 1;
      setState(() {});

      if (currentUserId != videoUserId) {
        await _sendCommentNotification(videoUserId, currentUserDisplayName, video);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment posted!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error posting comment')),
      );
    }
  }

  Future<void> _sendCommentNotification(String videoUserId, String commenterName, Map<String, dynamic> video) async {
    try {
      const String oneSignalAppId = '8ad10111-3d90-4ec2-a96d-28f6220ab3a0';
      const String oneSignalApiUrl = 'https://api.onesignal.com/notifications';
      final targetUserSnapshot = await _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('onesignal_player_id')
          .get();
      if (!targetUserSnapshot.exists) {
        return;
      }
      final String playerId = targetUserSnapshot.value.toString();
      const String title = '💬 New Comment!';
      final String content = '$commenterName commented on your video';
      const String clickUrl = 'https://fluzar.com/deep-redirect';
      const String largeIcon = 'https://img.onesignal.com/tmp/a74d2f7f-f359-4df4-b7ed-811437987e91/oxcPer7LSBS4aCGcVMi3_120x120%20app%20logo%20grande%20con%20sfondo%20bianco.png?_gl=1*1x2tx4r*_gcl_au*NjI1OTE1MTUyLjE3NTI0Mzk0Nzc.*_ga*MTY2MzE2MzA0MC4xNzUyNDM5NDc4*_ga_Z6LSTXWLPN*czE3NTI0NTEwMDkkbzMkZzAkdDE3NTI0NTEwMDkkajYwJGwwJGgyOTMzMzMxODk';

      final Map<String, dynamic> payload = {
        'app_id': oneSignalAppId,
        'include_player_ids': [playerId],
        'channel_for_external_user_ids': 'push',
        'headings': {'en': title},
        'contents': {'en': content},
        'url': clickUrl,
        'chrome_web_icon': largeIcon,
        'data': {
          'type': 'video_comment',
          'from_user_id': FirebaseAuth.instance.currentUser?.uid,
          'from_display_name': commenterName,
          'video_id': video['id'],
          'video_title': video['title'] ?? 'Your video',
        },
      };

      await http.post(
        Uri.parse(oneSignalApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic NGEwMGZmMDItY2RkNy00ZDc3LWI0NzEtZGYzM2FhZWU1OGUz',
        },
        body: jsonEncode(payload),
      );
    } catch (_) {}
  }

  void _showCommentsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _buildCommentsSheet(widget.videoId, widget.videoOwnerId),
      ),
    );
  }
  
  // New: open replies given a parent comment id and optional reply to highlight
  Future<void> _openRepliesForParent(String parentCommentId, String? highlightReplyId) async {
    try {
      final snap = await _database
          .child('users')
          .child('users')
          .child(widget.videoOwnerId)
          .child('videos')
          .child(widget.videoId)
          .child('comments')
          .child(parentCommentId)
          .get();
      if (!mounted) return;
      if (snap.exists && snap.value is Map) {
        final parent = Map<String, dynamic>.from(snap.value as Map);
        parent['id'] = parentCommentId;
        _showRepliesSheet(parent, highlightReplyId: highlightReplyId);
      } else {
        // Fallback: show comments list
        _showCommentsSheet();
      }
    } catch (e) {
      if (!mounted) return;
      _showCommentsSheet();
    }
  }
  
  // Inizializza le animazioni per le stelle dei commenti/replies
  void _initializeCommentStarAnimation(String commentId) {
    if (!_commentStarAnimationControllers.containsKey(commentId)) {
      final controller = AnimationController(
        duration: Duration(milliseconds: 600),
        vsync: this,
      );
      
      final scaleAnimation = Tween<double>(
        begin: 1.0,
        end: 1.6,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.elasticOut,
      ));
      
      final rotationAnimation = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOutBack,
      ));
      
      _commentStarAnimationControllers[commentId] = controller;
      _commentStarScaleAnimations[commentId] = scaleAnimation;
      _commentStarRotationAnimations[commentId] = rotationAnimation;
    }
  }
  
  Widget _buildCommentsSheet(String videoId, String videoOwnerId) {
    final TextEditingController commentController = TextEditingController();
    final FocusNode commentFocusNode = FocusNode();
    final String? highlightId = widget.highlightCommentId;
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.7, // Altezza fissa al 70% dello schermo
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? Color(0xFF1E1E1E) 
            : Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle della tendina
          Container(
            margin: EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header con titolo e conteggio commenti (minimal)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Comments',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white70 
                          : Colors.black54,
                    ),
                  ),
                  SizedBox(width: 6),
                  FutureBuilder<int>(
                    future: _getCommentsCount(videoId, videoOwnerId),
                    builder: (context, snapshot) {
                      final commentCount = snapshot.data ?? 0;
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Color(0xFF6C63FF).withOpacity(0.8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          commentCount.toString(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          
          // Lista commenti con StreamBuilder per aggiornamenti in tempo reale
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: _database
                  .child('users')
                  .child('users')
                  .child(videoOwnerId)
                  .child('videos')
                  .child(videoId)
                  .child('comments')
                  .onValue,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading comments',
                      style: TextStyle(color: Colors.red),
                    ),
                  );
                }
                
                if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                  return Container(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: 40),
                          Icon(
                            Icons.comment_outlined,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No comments yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Be the first to comment!',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                          SizedBox(height: 40),
                        ],
                      ),
                    ),
                  );
                }
                
                // iOS: i commenti possono arrivare come Map o List
                final dynamic rawComments = snapshot.data!.snapshot.value;
                Map<dynamic, dynamic>? commentsData;
                if (rawComments is Map) {
                  commentsData = rawComments;
                } else if (rawComments is List) {
                  commentsData = {
                    for (int i = 0; i < rawComments.length; i++)
                      if (rawComments[i] != null) i.toString(): rawComments[i]
                  };
                } else {
                  commentsData = null;
                }
                if (commentsData == null || commentsData.isEmpty) {
                  return Container(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: 40),
                          Icon(
                            Icons.comment_outlined,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No comments yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Be the first to comment!',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                          SizedBox(height: 40),
                        ],
                      ),
                    ),
                  );
                }
                
                // Converti i commenti in lista e ordina per timestamp
                List<Map<String, dynamic>> comments = [];
                commentsData.forEach((commentId, commentData) {
                  if (commentData is Map) {
                    final comment = Map<String, dynamic>.from(commentData);
                    comment['id'] = commentId;
                    comments.add(comment);
                  }
                });
                
                // Se c'è un commento da evidenziare, portalo in cima alla lista
                if (highlightId != null && highlightId.isNotEmpty) {
                  comments.sort((a, b) {
                    if (a['id'] == highlightId) return -1;
                    if (b['id'] == highlightId) return 1;
                    final at = a['timestamp'] ?? 0;
                    final bt = b['timestamp'] ?? 0;
                    return bt.compareTo(at);
                  });
                } else {
                  // Ordina per timestamp (più recenti prima)
                  comments.sort((a, b) {
                    final at = a['timestamp'] ?? 0;
                    final bt = b['timestamp'] ?? 0;
                    return bt.compareTo(at);
                  });
                }
                
                return ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    final isHighlighted = (highlightId != null && comment['id'] == highlightId);
                    final child = _buildCommentItem(comment, videoOwnerId);
                    if (!isHighlighted) return child;
                    return TweenAnimationBuilder<double>(
                      key: ValueKey('highlight_' + comment['id'].toString()),
                      tween: Tween(begin: 0.96, end: 1.0),
                      duration: Duration(milliseconds: 350),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, animatedChild) {
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFF6C63FF).withOpacity(0.25),
                                  blurRadius: 16,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: animatedChild,
                          ),
                        );
                      },
                      child: child,
                    );
                  },
                );
              },
            ),
          ),
          
          // Campo input commento
          Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Color(0xFF2A2A2A) 
                  : Colors.grey[50],
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Immagine profilo utente
                Container(
                  width: 32,
                  height: 32,
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
                  ),
                  child: ClipOval(
                    child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                        ? Image.network(
                            _profileImageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(Icons.person, color: Colors.white, size: 16),
                          )
                        : Icon(Icons.person, color: Colors.white, size: 16),
                  ),
                ),
                
                SizedBox(width: 12),
                
                // Campo di input
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[800] 
                          : Colors.white,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: TextField(
                      controller: commentController,
                      focusNode: commentFocusNode,
                      maxLines: null, // Permette infinite righe
                      textInputAction: TextInputAction.newline, // Cambia il tasto invio in "a capo"
                      keyboardType: TextInputType.multiline, // Abilita la tastiera multilinea
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        hintStyle: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      maxLength: 120,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(120),
                      ],
                      buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                    ),
                  ),
                ),
                
                SizedBox(width: 12),
                
                // Pulsante invia
                GestureDetector(
                  onTap: () async {
                    if (commentController.text.trim().isNotEmpty) {
                      await _submitComment(widget.videoId, widget.videoOwnerId, commentController.text.trim(), _videoData ?? {'id': widget.videoId, 'title': _videoData?['title']});
                      commentController.clear();
                      commentFocusNode.unfocus();
                      FocusScope.of(context).unfocus();
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF667eea), // Colore iniziale: blu violaceo
                          Color(0xFF764ba2), // Colore finale: viola
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * pi / 180), // 135 gradi
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.send,
                      color: Colors.white,
                      size: 18,
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
  
  Widget _buildCommentItem(Map<String, dynamic> comment, String videoOwnerId) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Converti timestamp in DateTime
    DateTime commentTime;
    if (comment['timestamp'] is int) {
      commentTime = DateTime.fromMillisecondsSinceEpoch(comment['timestamp']);
    } else {
      commentTime = DateTime.now();
    }
    
    // Load profile image dynamically for this comment
    final userId = comment['userId']?.toString() ?? '';
    final profileImageUrl = comment['userProfileImage']?.toString() ?? '';
    
    return FutureBuilder<String?>(
      future: userId.isNotEmpty ? _loadUserProfileImage(userId) : Future.value(null),
      builder: (context, snapshot) {
        final currentProfileImageUrl = snapshot.data ?? profileImageUrl;
    
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Immagine profilo utente
          GestureDetector(
            onTap: () {
              final uid = comment['userId']?.toString();
              if (uid != null && uid.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileEditPage(userId: uid),
                  ),
                );
              }
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Color(0xFF6C63FF).withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: ClipOval(
                child: currentProfileImageUrl.isNotEmpty
                    ? Image.network(
                        currentProfileImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFF6C63FF),
                                  Color(0xFF8B7CF6),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 16,
                            ),
                          );
                        },
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF6C63FF),
                              Color(0xFF8B7CF6),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
              ),
            ),
          ),
          
          SizedBox(width: 12),
          
          // Contenuto del commento
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nome utente e timestamp
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        final uid = comment['userId']?.toString();
                        if (uid != null && uid.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProfileEditPage(userId: uid),
                            ),
                          );
                        }
                      },
                      child: Text(
                        comment['userDisplayName'] ?? 'Anonymous',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      _formatTimestamp(commentTime),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 4),
                
                // Testo del commento
                Text(
                  comment['text'] ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.black87,
                    height: 1.3,
                  ),
                ),
                
                SizedBox(height: 8),
                
                // Pulsanti azioni (Reply, Star e View Replies)
                Row(
                  children: [
                    // Reply
                    GestureDetector(
                      onTap: () => _showRepliesSheet(comment),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.reply, size: 16, color: Colors.grey[600]),
                          SizedBox(width: 4),
                          Text(
                            'Reply',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    
                    SizedBox(width: 16),
                    
                    // Star comment
                    GestureDetector(
                      onTap: () => _handleCommentStar(comment),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _commentStarAnimationControllers[comment['id']] ??
                                  (() { _initializeCommentStarAnimation(comment['id']); return _commentStarAnimationControllers[comment['id']]!; })(),
                              builder: (context, child) {
                                final scaleAnimation = _commentStarScaleAnimations[comment['id']];
                                final rotationAnimation = _commentStarRotationAnimations[comment['id']];
                                final isStarred = (comment['star_users'] is Map) && (comment['star_users'][FirebaseAuth.instance.currentUser?.uid] == true);
                                return Transform.scale(
                                  scale: scaleAnimation?.value ?? 1.0,
                                  child: Transform.rotate(
                                    angle: rotationAnimation?.value ?? 0.0,
                                    child: isStarred
                                        ? ShaderMask(
                                            shaderCallback: (Rect bounds) {
                                              return LinearGradient(
                                                colors: [Color(0xFF6C63FF), Color(0xFFFF6B6B)],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ).createShader(bounds);
                                            },
                                            child: Icon(Icons.star, color: Colors.white, size: 18),
                                          )
                                        : Icon(Icons.star_border, size: 18, color: Colors.grey[600]),
                                  ),
                                );
                              },
                            ),
                            SizedBox(width: 4),
                            Text(
                              '${comment['star_count'] ?? 0}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    SizedBox(width: 16),
                    
                    // View replies if any
                    if ((comment['replies_count'] ?? 0) > 0)
                      GestureDetector(
                        onTap: () => _showRepliesSheet(comment),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.expand_more, size: 16, color: Colors.grey[600]),
                            SizedBox(width: 4),
                            Text(
                              '${comment['replies_count']} replies',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
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
      },
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  void _triggerCommentStarAnimation(String id) {
    if (!_commentStarAnimationControllers.containsKey(id)) {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );
      _commentStarAnimationControllers[id] = controller;
      _commentStarScaleAnimations[id] = Tween<double>(begin: 1.0, end: 1.6).animate(
        CurvedAnimation(parent: controller, curve: Curves.elasticOut),
      );
      _commentStarRotationAnimations[id] = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOutBack),
      );
    }
    _commentStarAnimationControllers[id]!.forward(from: 0.0);
  }

  bool _isCommentStarredByCurrentUser(Map<String, dynamic> item) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;
    
    final starUsers = item['star_users'];
    if (starUsers == null) return false;
    
    // Gestisci diversi tipi di dati per star_users (fix iOS)
    if (starUsers is Map) {
      return starUsers.containsKey(currentUser.uid);
    } else if (starUsers is List) {
      // Caso in cui star_users è una lista invece di una mappa
      return starUsers.contains(currentUser.uid);
    }
    
    return false;
  }

  Future<void> _handleCommentStar(Map<String, dynamic> comment) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final commentId = comment['id']?.toString();
    final videoId = widget.videoId;
    if (commentId == null) return;
    
    // Debounce per prevenire doppi tap (fix iOS)
    final now = DateTime.now();
    final lastTapTime = _lastStarTapTime[commentId];
    if (lastTapTime != null && now.difference(lastTapTime) < _starDebounceTime) {
      return; // Ignora il tap se troppo vicino al precedente
    }
    _lastStarTapTime[commentId] = now;
    
    try {
      final currentUserId = currentUser.uid;

      // Percorso commento
      final commentRef = _database
          .child('users')
          .child('users')
          .child(widget.videoOwnerId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(commentId);

      // Star users - Controlla sempre Firebase per lo stato attuale (fix iOS)
      final starUsersRef = commentRef.child('star_users');
      final userStarSnapshot = await starUsersRef.child(currentUserId).get();
      final hasUserStarred = userStarSnapshot.exists;

      // Star count - Leggi sempre da Firebase per sincronizzazione (fix iOS)
      final starCountSnap = await commentRef.child('star_count').get();
      int currentStarCount = 0;
      if (starCountSnap.exists) {
        final v = starCountSnap.value;
        if (v is int) currentStarCount = v; else currentStarCount = int.tryParse(v.toString()) ?? 0;
      }

      int newStarCount;
      if (hasUserStarred) {
         // Toggle off
         _triggerCommentStarAnimation(commentId);
        await starUsersRef.child(currentUserId).remove();
        newStarCount = math.max(0, currentStarCount - 1); // Previeni valori negativi (fix iOS)
      } else {
         // Toggle on
        _triggerCommentStarAnimation(commentId);
        await starUsersRef.child(currentUserId).set(true);
        newStarCount = currentStarCount + 1;

        // Notifica al proprietario del commento (se diverso dall'utente corrente)
        final commentOwnerId = comment['userId'] as String?;
        if (commentOwnerId != null && commentOwnerId != currentUserId) {
          final notificationStarRef = _database
              .child('users')
              .child('users')
              .child(commentOwnerId)
              .child('notificationstars')
              .child('${commentId}_${currentUserId}');

          final notificationStarData = {
            'id': '${commentId}_${currentUserId}',
            'commentId': commentId,
            'videoId': videoId,
            'videoTitle': comment['videoTitle'] ?? 'Untitled Video',
            'videoOwnerId': widget.videoOwnerId,
            'commentOwnerId': commentOwnerId,
            'starUserId': currentUserId,
            'starUserDisplayName': currentUser.displayName ?? 'Anonymous',
            'starUserProfileImage': _profileImageUrl ?? currentUser.photoURL ?? '',
            'timestamp': ServerValue.timestamp,
            'type': 'comment_star',
            'read': false,
          };
          await notificationStarRef.set(notificationStarData);
        }
      }

      // Aggiorna il conteggio totale delle stelle usando transazione atomica
      await commentRef.child('star_count').set(newStarCount);

      // Aggiorna lo stato locale DOPO aver verificato Firebase (fix iOS)
      if (mounted) {
        setState(() {
          comment['star_count'] = newStarCount;
          if (comment['star_users'] == null) comment['star_users'] = {};
          
          // Forza l'aggiornamento dello stato locale basato su Firebase
          if (hasUserStarred) {
            comment['star_users']?.remove(currentUserId);
          } else {
            comment['star_users']?[currentUserId] = true;
          }
        });
      }
    } catch (e) {
      print('Errore nell\'aggiornamento delle stelle del commento: $e');
      // In caso di errore, ricarica i dati dal database per sincronizzare (fix iOS)
      if (mounted) {
        try {
          // Ricarica lo stato attuale da Firebase per sincronizzare
          final commentRef = _database
              .child('users')
              .child('users')
              .child(widget.videoOwnerId)
              .child('videos')
              .child(videoId)
              .child('comments')
              .child(commentId);
          
          final refreshSnapshot = await commentRef.get();
          if (refreshSnapshot.exists && refreshSnapshot.value is Map && mounted) {
            final refreshedComment = Map<String, dynamic>.from(refreshSnapshot.value as Map);
            setState(() {
              comment['star_count'] = refreshedComment['star_count'] ?? 0;
              comment['star_users'] = refreshedComment['star_users'] ?? {};
            });
          }
        } catch (refreshError) {
          print('Error refreshing comment state: $refreshError');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Errore nell\'aggiornamento delle stelle del commento')),
        );
      }
    }
  }

  Future<void> _handleReplyStar(Map<String, dynamic> reply) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final replyId = reply['id']?.toString();
    final videoId = widget.videoId;
    final parentCommentId = reply['parentCommentId']?.toString();
    if (replyId == null || parentCommentId == null) return;
    
    // Debounce per prevenire doppi tap (fix iOS)
    final now = DateTime.now();
    final lastTapTime = _lastStarTapTime[replyId];
    if (lastTapTime != null && now.difference(lastTapTime) < _starDebounceTime) {
      return; // Ignora il tap se troppo vicino al precedente
    }
    _lastStarTapTime[replyId] = now;
    
    try {
      final currentUserId = currentUser.uid;

      final replyRef = _database
          .child('users')
          .child('users')
          .child(widget.videoOwnerId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(parentCommentId)
          .child('replies')
          .child(replyId);

      // Star users - Controlla sempre Firebase per lo stato attuale (fix iOS)
      final starUsersRef = replyRef.child('star_users');
      final userStarSnapshot = await starUsersRef.child(currentUserId).get();
      final hasUserStarred = userStarSnapshot.exists;

      // Star count - Leggi sempre da Firebase per sincronizzazione (fix iOS)
      final starCountSnap = await replyRef.child('star_count').get();
      int currentStarCount = 0;
      if (starCountSnap.exists) {
        final v = starCountSnap.value;
        if (v is int) currentStarCount = v; else currentStarCount = int.tryParse(v.toString()) ?? 0;
      }

      int newStarCount;
      if (hasUserStarred) {
        _triggerCommentStarAnimation(replyId);
        await starUsersRef.child(currentUserId).remove();
        newStarCount = math.max(0, currentStarCount - 1); // Previeni valori negativi (fix iOS)
      } else {
        _triggerCommentStarAnimation(replyId);
        await starUsersRef.child(currentUserId).set(true);
        newStarCount = currentStarCount + 1;

        final replyOwnerId = reply['userId']?.toString();
        if (replyOwnerId != null && replyOwnerId != currentUserId) {
          final notificationStarRef = _database
              .child('users')
              .child('users')
              .child(replyOwnerId)
              .child('notificationstars')
              .child('${replyId}_${currentUserId}');

          final notificationStarData = {
            'id': '${replyId}_${currentUserId}',
            'replyId': replyId,
            'commentId': parentCommentId,
            'videoId': videoId,
            'videoTitle': reply['videoTitle'] ?? 'Untitled Video',
            'videoOwnerId': widget.videoOwnerId,
            'replyOwnerId': replyOwnerId,
            'starUserId': currentUserId,
            'starUserDisplayName': currentUser.displayName ?? 'Anonymous',
            'starUserProfileImage': _profileImageUrl ?? currentUser.photoURL ?? '',
            'timestamp': ServerValue.timestamp,
            'type': 'reply_star',
            'read': false,
          };
          await notificationStarRef.set(notificationStarData);
        }
      }

      // Aggiorna il conteggio totale delle stelle usando transazione atomica
      await replyRef.child('star_count').set(newStarCount);

      // Aggiorna lo stato locale DOPO aver verificato Firebase (fix iOS)
      if (mounted) {
        setState(() {
          reply['star_count'] = newStarCount;
          if (reply['star_users'] == null) reply['star_users'] = {};
          
          // Forza l'aggiornamento dello stato locale basato su Firebase
          if (hasUserStarred) {
            reply['star_users']?.remove(currentUserId);
          } else {
            reply['star_users']?[currentUserId] = true;
          }
        });
      }
    } catch (e) {
      print('Errore nell\'aggiornamento delle stelle della risposta: $e');
      // In caso di errore, ricarica i dati dal database per sincronizzare (fix iOS)
      if (mounted) {
        try {
          // Ricarica lo stato attuale da Firebase per sincronizzare
          final replyRef = _database
              .child('users')
              .child('users')
              .child(widget.videoOwnerId)
              .child('videos')
              .child(videoId)
              .child('comments')
              .child(parentCommentId)
              .child('replies')
              .child(replyId);
          
          final refreshSnapshot = await replyRef.get();
          if (refreshSnapshot.exists && refreshSnapshot.value is Map && mounted) {
            final refreshedReply = Map<String, dynamic>.from(refreshSnapshot.value as Map);
            setState(() {
              reply['star_count'] = refreshedReply['star_count'] ?? 0;
              reply['star_users'] = refreshedReply['star_users'] ?? {};
            });
          }
        } catch (refreshError) {
          print('Error refreshing reply state: $refreshError');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Errore nell\'aggiornamento delle stelle della risposta')),
        );
      }
    }
  }

  Future<void> _submitReply(Map<String, dynamic> parentComment, String replyText) async {
    // Send OneSignal push to parent comment owner
    Future<void> _sendReplyNotification(String parentCommentOwnerId, String replierName, Map<String, dynamic> video, String parentCommentId, String replyId) async {
      try {
        const String oneSignalAppId = '8ad10111-3d90-4ec2-a96d-28f6220ab3a0';
        const String oneSignalApiUrl = 'https://api.onesignal.com/notifications';
        const String largeIcon = 'https://img.onesignal.com/tmp/a74d2f7f-f359-4df4-b7ed-811437987e91/oxcPer7LSBS4aCGcVMi3_120x120%20app%20logo%20grande%20con%20sfondo%20bianco.png?_gl=1*1x2tx4r*_gcl_au*NjI1OTE1MTUyLjE3NTI0Mzk0Nzc.*_ga*MTY2MzE2MzA';

        // Recupera OneSignal playerId del destinatario
        final targetUserSnapshot = await _database
            .child('users')
            .child('users')
            .child(parentCommentOwnerId)
            .child('onesignal_player_id')
            .get();
        if (!targetUserSnapshot.exists || targetUserSnapshot.value == null) return;
        final String playerId = targetUserSnapshot.value.toString();

        final String title = 'New reply';
        final String content = '$replierName replied to your comment';
        final String clickUrl = 'https://viralyst.app/video/${video['id']}?open=replies&commentId=$parentCommentId&replyId=$replyId';

        final Map<String, dynamic> payload = {
          'app_id': oneSignalAppId,
          'include_player_ids': [playerId],
          'channel_for_external_user_ids': 'push',
          'headings': {'en': title},
          'contents': {'en': content},
          'url': clickUrl,
          'chrome_web_icon': largeIcon,
          'data': {
            'type': 'video_reply',
            'from_user_id': FirebaseAuth.instance.currentUser?.uid,
            'from_display_name': replierName,
            'video_id': video['id'],
            'parent_comment_id': parentCommentId,
            'reply_id': replyId,
            'video_title': video['title'] ?? 'Your video',
          },
        };

        await http.post(
          Uri.parse(oneSignalApiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Basic NGEwMGZmMDItY2RkNy00ZDc3LWI0NzEtZGYzM2FhZWU1OGUz',
          },
          body: jsonEncode(payload),
        );
      } catch (_) {}
    }

    try {
      final parentCommentId = parentComment['id'] as String;
      final videoId = widget.videoId;
      final replyId = DateTime.now().millisecondsSinceEpoch.toString();
      final replyRef = _database
          .child('users')
          .child('users')
          .child(widget.videoOwnerId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(parentCommentId)
          .child('replies')
          .child(replyId);

      final currentUser = FirebaseAuth.instance.currentUser!;
      final currentUserId = currentUser.uid;
      final currentUserDisplayName = currentUser.displayName ?? 'Anonymous';
      final currentUserProfileImage = currentUser.photoURL;
      final parentCommentOwnerId = parentComment['userId']?.toString();

      final replyData = {
        'id': replyId,
        'text': replyText,
        'userId': currentUserId,
        'userDisplayName': currentUserDisplayName,
        'userProfileImage': currentUserProfileImage,
        'timestamp': ServerValue.timestamp,
        'parentCommentId': parentCommentId,
        'videoId': videoId,
        'star_count': 0,
        'star_users': {},
      };

      await replyRef.set(replyData);

      // Salva la reply nella cartella notificationcomment del proprietario del commento
      if (parentCommentOwnerId != null && parentCommentOwnerId.isNotEmpty && parentCommentOwnerId != currentUserId) {
        final notificationReplyRef = _database
            .child('users')
            .child('users')
            .child(parentCommentOwnerId)
            .child('notificationcomment')
            .child('${parentCommentId}_reply_${replyId}');
 
        final notificationReplyData = {
          'id': '${parentCommentId}_reply_${replyId}',
          'text': replyText,
          'userId': currentUserId,
          'userDisplayName': currentUserDisplayName,
          'userProfileImage': currentUserProfileImage,
          'timestamp': ServerValue.timestamp,
          'videoId': videoId,
          'videoTitle': parentComment['videoTitle'] ?? 'Untitled Video',
          'videoOwnerId': widget.videoOwnerId,
          'parentCommentId': parentCommentId,
          'type': 'reply',
          'read': false,
          'replies_count': 0,
          'star_count': 0,
          'star_users': {},
        };
 
        await notificationReplyRef.set(notificationReplyData);

        // OneSignal push (english)
        await _sendReplyNotification(parentCommentOwnerId, currentUserDisplayName, {
          'id': videoId,
          'title': parentComment['videoTitle'] ?? 'Your video',
        }, parentCommentId, replyId);
      }
 
      // Aggiorna counter risposte sul commento padre
      final parentRef = _database
          .child('users')
          .child('users')
          .child(widget.videoOwnerId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(parentCommentId);
      final repliesCountSnapshot = await parentRef.child('replies_count').get();
      int currentRepliesCount = 0;
      if (repliesCountSnapshot.exists) {
        final v = repliesCountSnapshot.value;
        if (v is int) currentRepliesCount = v; else currentRepliesCount = int.tryParse(v.toString()) ?? 0;
      }
      await parentRef.child('replies_count').set(currentRepliesCount + 1);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reply posted!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error posting reply')),
      );
    }
  }

  void _showRepliesSheet(Map<String, dynamic> parentComment, {String? highlightReplyId}) {
    final TextEditingController replyController = TextEditingController();
    final FocusNode replyFocusNode = FocusNode();
    final ScrollController repliesScrollController = ScrollController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header with original comment
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                children: [
                  Center(
                    child: Text(
                      'Replies',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () {
                            final uid = parentComment['userId']?.toString();
                            if (uid != null && uid.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProfileEditPage(userId: uid),
                                ),
                              );
                            }
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.2), width: 1),
                            ),
                                                      child: FutureBuilder<String?>(
                            future: _loadUserProfileImage(parentComment['userId']?.toString() ?? ''),
                            builder: (context, snapshot) {
                              final currentProfileImageUrl = snapshot.data ?? parentComment['userProfileImage']?.toString() ?? '';
                              return ClipOval(
                                child: currentProfileImageUrl.isNotEmpty
                                    ? Image.network(
                                        currentProfileImageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Color(0xFF6C63FF),
                                                  Color(0xFF8B7CF6),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.person,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          );
                                        },
                                      )
                                    : Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFF6C63FF),
                                              Color(0xFF8B7CF6),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.person,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                              );
                            },
                          ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    parentComment['userDisplayName'] ?? 'Anonymous',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatTimestamp(DateTime.fromMillisecondsSinceEpoch(parentComment['timestamp'] ?? DateTime.now().millisecondsSinceEpoch)),
                                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                parentComment['text'] ?? '',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Replies list
            Expanded(
              child: StreamBuilder<DatabaseEvent>(
                stream: _database
                    .child('users')
                    .child('users')
                    .child(widget.videoOwnerId)
                    .child('videos')
                    .child(widget.videoId)
                    .child('comments')
                    .child(parentComment['id'])
                    .child('replies')
                    .onValue,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading replies', style: TextStyle(color: Colors.red[400])));
                  }
                  final snap = snapshot.data?.snapshot;
                  if (snap == null || snap.value == null) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            SizedBox(height: 40),
                            Icon(Icons.reply_outlined, size: 48, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No replies yet', style: TextStyle(fontSize: 16, color: Colors.grey)),
                            SizedBox(height: 8),
                            Text('Be the first to reply!', style: TextStyle(fontSize: 14, color: Colors.grey)),
                            SizedBox(height: 40),
                          ],
                        ),
                      ),
                    );
                  }
                  // iOS: le replies possono essere Map o List
                  final dynamic rawReplies = snap.value;
                  List<Map<String, dynamic>> replies;
                  if (rawReplies is Map) {
                    replies = rawReplies.entries.map((e) {
                      final m = Map<String, dynamic>.from(e.value as Map);
                      m['id'] = e.key.toString();
                      return m;
                    }).toList();
                  } else if (rawReplies is List) {
                    replies = [];
                    for (int i = 0; i < rawReplies.length; i++) {
                      final item = rawReplies[i];
                      if (item is Map) {
                        final m = Map<String, dynamic>.from(item);
                        m['id'] = i.toString();
                        replies.add(m);
                      }
                    }
                  } else {
                    replies = [];
                  }
                  replies = replies
                    
                    ..sort((a, b) => ((b['timestamp'] ?? 0) as int).compareTo((a['timestamp'] ?? 0) as int));

                  return ListView.builder(
                    controller: repliesScrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: replies.length,
                    itemBuilder: (context, index) {
                      final reply = replies[index];
                      final isHighlighted = (highlightReplyId != null && reply['id'] == highlightReplyId);
                      final child = _buildReplyItem(reply);
                      
                      // Scroll automatico alla reply evidenziata dopo che la lista è stata costruita
                      if (isHighlighted && highlightReplyId != null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (repliesScrollController.hasClients) {
                            final highlightedIndex = replies.indexWhere((r) => r['id'] == highlightReplyId);
                            if (highlightedIndex != -1) {
                              repliesScrollController.animateTo(
                                highlightedIndex * 120.0, // Stima dell'altezza di ogni reply
                                duration: Duration(milliseconds: 800),
                                curve: Curves.easeInOutCubic,
                              );
                            }
                          }
                          
                          // Evidenziazione gestita dallo stile del container (ombre e gradient)
                          // Niente animazione stella per la reply evidenziata
                        });
                      }
                      
                      if (!isHighlighted) return child;
                      return TweenAnimationBuilder<double>(
                        key: ValueKey('highlight_reply_' + reply['id'].toString()),
                        tween: Tween(begin: 0.96, end: 1.0),
                        duration: Duration(milliseconds: 350),
                        curve: Curves.easeOutBack,
                        builder: (context, scale, animatedChild) {
                          final isDark = Theme.of(context).brightness == Brightness.dark;
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: isDark ? Colors.black.withOpacity(0.35) : Colors.black.withOpacity(0.12),
                                    blurRadius: isDark ? 22 : 18,
                                    spreadRadius: isDark ? 1 : 0,
                                    offset: const Offset(0, 8),
                                  ),
                                  BoxShadow(
                                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.5),
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
                                          Colors.white.withOpacity(0.18),
                                          Colors.white.withOpacity(0.08),
                                        ]
                                      : [
                                          Colors.white.withOpacity(0.28),
                                          Colors.white.withOpacity(0.18),
                                        ],
                                ),
                              ),
                              child: animatedChild ?? child,
                            ),
                          );
                        },
                        child: child,
                      );
                    },
                  );
                },
              ),
            ),
            // Input
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, -2)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFFFF6B6B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: ClipOval(
                      child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                          ? Image.network(
                              _profileImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Icon(Icons.person, color: Colors.white, size: 16),
                            )
                          : Icon(Icons.person, color: Colors.white, size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.white,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: TextField(
                        controller: replyController,
                        focusNode: replyFocusNode,
                        maxLines: null, // Permette infinite righe
                        textInputAction: TextInputAction.newline, // Cambia il tasto invio in "a capo"
                        keyboardType: TextInputType.multiline, // Abilita la tastiera multilinea
                        decoration: InputDecoration(
                          hintText: 'Add a reply...',
                          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        maxLength: 120,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(120),
                        ],
                        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                        onSubmitted: (text) async {
                          if (text.trim().isNotEmpty) {
                            await _submitReply(parentComment, text.trim());
                            replyController.clear();
                            replyFocusNode.unfocus();
                            FocusScope.of(context).unfocus();
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () async {
                      if (replyController.text.trim().isNotEmpty) {
                        await _submitReply(parentComment, replyController.text.trim());
                        replyController.clear();
                        replyFocusNode.unfocus();
                        FocusScope.of(context).unfocus();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ).whenComplete(() {
    // Ferma tutte le animazioni di pulsazione quando si chiude la tendina
    if (highlightReplyId != null) {
      final controller = _commentStarAnimationControllers[highlightReplyId];
      if (controller != null && controller.isAnimating) {
        controller.stop();
        controller.reset();
      }
    }
    // Dispose del ScrollController
    repliesScrollController.dispose();
  });
  }

  Widget _buildReplyItem(Map<String, dynamic> reply) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final DateTime replyTime = reply['timestamp'] is int
        ? DateTime.fromMillisecondsSinceEpoch(reply['timestamp'])
        : DateTime.now();
    
    // Load profile image dynamically for this reply
    final userId = reply['userId']?.toString() ?? '';
    final profileImageUrl = reply['userProfileImage']?.toString() ?? '';
    
    return FutureBuilder<String?>(
      future: userId.isNotEmpty ? _loadUserProfileImage(userId) : Future.value(null),
      builder: (context, snapshot) {
        final currentProfileImageUrl = snapshot.data ?? profileImageUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.1), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.grey[400]!, width: 2),
                bottom: BorderSide(color: Colors.grey[400]!, width: 2),
              ),
            ),
          ),
          // Immagine profilo utente (reply)
          GestureDetector(
            onTap: () {
              final uid = reply['userId']?.toString();
              if (uid != null && uid.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileEditPage(userId: uid),
                  ),
                );
              }
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.2), width: 1),
              ),
              child: ClipOval(
                child: currentProfileImageUrl.isNotEmpty
                    ? Image.network(
                        currentProfileImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFF6C63FF),
                                  Color(0xFF8B7CF6),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 14,
                            ),
                          );
                        },
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF6C63FF),
                              Color(0xFF8B7CF6),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        final uid = reply['userId']?.toString();
                        if (uid != null && uid.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProfileEditPage(userId: uid),
                            ),
                          );
                        }
                      },
                      child: Text(
                        reply['userDisplayName'] ?? 'Anonymous',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_formatTimestamp(replyTime), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  reply['text'] ?? '',
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87, height: 1.3),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _handleReplyStar(reply),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _commentStarAnimationControllers[reply['id']] ?? AnimationController(duration: Duration.zero, vsync: this),
                        builder: (context, child) {
                          final scaleAnimation = _commentStarScaleAnimations[reply['id']];
                          final rotationAnimation = _commentStarRotationAnimations[reply['id']];
                          final isStarred = (reply['star_users'] is Map) && (reply['star_users'][FirebaseAuth.instance.currentUser?.uid] == true);
                          return Transform.scale(
                            scale: scaleAnimation?.value ?? 1.0,
                            child: Transform.rotate(
                              angle: rotationAnimation?.value ?? 0.0,
                              child: isStarred
                                  ? ShaderMask(
                                      shaderCallback: (Rect bounds) {
                                        return const LinearGradient(
                                          colors: [Color(0xFF6C63FF), Color(0xFFFF6B6B)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ).createShader(bounds);
                                      },
                                      child: const Icon(Icons.star, color: Colors.white, size: 16),
                                    )
                                  : Icon(Icons.star_border, color: Colors.grey[600], size: 16),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      Text('${reply['star_count'] ?? 0}', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
      },
    );
  }

  @override
  void dispose() {
    _disposeController();
    
    // Dispose dei controller delle animazioni per le stelle
    for (final controller in _commentStarAnimationControllers.values) {
      controller.dispose();
    }
    _commentStarAnimationControllers.clear();
    _commentStarScaleAnimations.clear();
    _commentStarRotationAnimations.clear();
    
    // Pulisci la cache del debounce (fix iOS)
    _lastStarTapTime.clear();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isOwner = FirebaseAuth.instance.currentUser?.uid == widget.videoOwnerId;
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark ? const Color(0xFF121212) : Colors.black,
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _errorMessage != null
                ? Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _isInitialized
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          // Icona di back minimal in alto a sinistra
                          Positioned(
                            top: 40,
                            left: 16,
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
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
                                                     Center(
                             child: Container(
                               width: MediaQuery.of(context).size.width * 0.95,
                               margin: const EdgeInsets.only(top: 24), // padding nero in alto per freccia su verticali
                               decoration: BoxDecoration(
                                 borderRadius: BorderRadius.circular(20),
                                 color: Colors.black, // Area fuori dai bordi sarà nera
                               ),
                               child: ClipRRect(
                                 borderRadius: BorderRadius.circular(20),
                                 child: AspectRatio(
                                   aspectRatio: _controller!.value.aspectRatio == 0
                                       ? 16 / 9
                                       : _controller!.value.aspectRatio,
                                   child: VideoPlayer(_controller!),
                                 ),
                               ),
                             ),
                           ),
                          // Overlay per il tap play/pause centrato sul video
                          Center(
                            child: Container(
                              width: MediaQuery.of(context).size.width * 0.95,
                              child: AspectRatio(
                                aspectRatio: _controller!.value.aspectRatio == 0
                                    ? 16 / 9
                                    : _controller!.value.aspectRatio,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                                                     onTap: () async {
                                     // Fix iOS: Aggiungi controlli di sicurezza
                                     if (_controller == null || !_controller!.value.isInitialized) return;
                                     
                                     try {
                                       if (_controller!.value.isPlaying) {
                                         await _controller!.pause();
                                       } else {
                                         await _controller!.play();
                                       }
                                       if (mounted) setState(() {});
                                     } catch (e) {
                                       print('Error toggling video playback: $e');
                                     }
                                   },
                                   onDoubleTap: () async {
                                     // restart quickly on double tap (fix iOS)
                                     if (_controller == null || !_controller!.value.isInitialized) return;
                                     
                                     try {
                                       await _controller!.seekTo(Duration.zero);
                                       await _controller!.play();
                                       if (mounted) setState(() {});
                                     } catch (e) {
                                       print('Error restarting video: $e');
                                     }
                                   },
                                  child: AnimatedOpacity(
                                    opacity: _controller!.value.isPlaying ? 0.0 : 1.0,
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
                         if (isOwner)
                           Positioned(
                             right: 16,
                             bottom: 154, // Alzato di 1cm (38px) da 116 a 154
                             child: Material(
                               color: Colors.black45,
                               shape: const CircleBorder(),
                               child: IconButton(
                                 icon: const Icon(Icons.star, color: Colors.white),
                                 tooltip: 'View stars',
                                 onPressed: () => _showStarredUsersSheetQuick(),
                               ),
                             ),
                           ),
                          // Comment button (opens bottom sheet)
                          Positioned(
                            right: 16,
                            bottom: 94, // Alzato di 1cm (38px) da 56 a 94
                            child: Material(
                              color: Colors.black45,
                              shape: const CircleBorder(),
                              child: IconButton(
                                icon: const Icon(Icons.comment, color: Colors.white),
                                onPressed: _showCommentsSheet,
                                tooltip: 'Comments',
                              ),
                            ),
                          ),
                          // Bottom progress bar (seconds)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 8, // Spostata più in alto di 2mm (8px)
                            child: (_controller != null)
                                ? ValueListenableBuilder<VideoPlayerValue>(
                                    valueListenable: _controller!,
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
                                                                                                                                      // Progress bar con area di cliccaggio estesa
                                             Container(
                                               height: 24, // Area di cliccaggio estesa verticalmente
                                               child: GestureDetector(
                                                 onTapDown: (details) {
                                                   // Calcola la posizione del tap relativa alla progress bar
                                                   final RenderBox renderBox = context.findRenderObject() as RenderBox;
                                                   final localPosition = renderBox.globalToLocal(details.globalPosition);
                                                   final progressBarWidth = renderBox.size.width - 32; // Sottrai il padding
                                                   final tapPosition = localPosition.dx - 16; // Sottrai il padding sinistro
                                                   
                                                   // Calcola la percentuale e il tempo corrispondente (fix iOS)
                                                   if (progressBarWidth > 0 && _controller != null && _controller!.value.isInitialized) {
                                                     try {
                                                       final percentage = (tapPosition / progressBarWidth).clamp(0.0, 1.0);
                                                       final newTime = (max * percentage).toInt();
                                                       _controller!.seekTo(Duration(milliseconds: newTime));
                                                       
                                                       // Attiva l'effetto di interazione
                                                       if (!_isProgressInteracting && mounted) {
                                                         setState(() => _isProgressInteracting = true);
                                                       }
                                                       
                                                       // Disattiva l'effetto dopo un breve delay
                                                       Future.delayed(Duration(milliseconds: 300), () {
                                                         if (mounted && _isProgressInteracting) {
                                                           setState(() => _isProgressInteracting = false);
                                                         }
                                                       });
                                                     } catch (e) {
                                                       print('Error seeking video: $e');
                                                     }
                                                   }
                                                 },
                                                 child: Align(
                                                   alignment: Alignment.bottomCenter,
                                                   child: AnimatedContainer(
                                                     duration: Duration(milliseconds: 200),
                                                     height: _isProgressInteracting ? 8 : 4,
                                                     child: SliderTheme(
                                                       data: SliderThemeData(
                                                         thumbShape: RoundSliderThumbShape(
                                                           enabledThumbRadius: _isProgressInteracting ? 6 : 0,
                                                         ),
                                                         trackHeight: _isProgressInteracting ? 8 : 4,
                                                         activeTrackColor: Colors.white,
                                                         inactiveTrackColor: Colors.white.withOpacity(0.3),
                                                         thumbColor: _isProgressInteracting ? Colors.white : Colors.transparent,
                                                         overlayColor: Colors.white.withOpacity(0.2),
                                        ),
                                        child: Slider(
                                          value: clamped,
                                          min: 0.0,
                                          max: max,
                                          onChanged: (v) {
                                            // Fix iOS: Aggiungi controlli di sicurezza
                                            if (_controller != null && _controller!.value.isInitialized) {
                                              try {
                                                _controller!.seekTo(Duration(milliseconds: v.toInt()));
                                                if (!_isProgressInteracting && mounted) {
                                                  setState(() => _isProgressInteracting = true);
                                                }
                                              } catch (e) {
                                                print('Error seeking video via slider: $e');
                                              }
                                            }
                                          },
                                          onChangeEnd: (_) {
                                            if (_isProgressInteracting && mounted) {
                                              setState(() => _isProgressInteracting = false);
                                            }
                                          },
                                                         // Permette di cliccare ovunque nella progress bar per navigare
                                                         onChangeStart: (_) {
                                                           if (!_isProgressInteracting && mounted) {
                                                             setState(() => _isProgressInteracting = true);
                                                           }
                                                         },
                                                       ),
                                                     ),
                                                   ),
                                                 ),
                                               ),
                                             ),
                                             
                                             // Spazio aumentato tra progress bar e indicatori di tempo
                                             SizedBox(height: 12),
                                             
                                             // Indicatori di tempo
                                             Padding(
                                               padding: EdgeInsets.symmetric(horizontal: 4),
                                               child: Row(
                                                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                 children: [
                                                   // Tempo corrente
                                                   Text(
                                                     '${currentMinutes.toString().padLeft(2, '0')}:${currentSeconds.toString().padLeft(2, '0')}',
                                                     style: TextStyle(
                                                       color: Colors.white,
                                                       fontSize: 12,
                                                       fontWeight: FontWeight.w500,
                                                     ),
                                                   ),
                                                   
                                                   // Tempo totale
                                                   Text(
                                                     '${totalMinutes.toString().padLeft(2, '0')}:${totalSeconds.toString().padLeft(2, '0')}',
                                                     style: TextStyle(
                                                       color: Colors.white.withOpacity(0.7),
                                                       fontSize: 12,
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
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      )
                    : const Text(
                        'Player non inizializzato',
                        style: TextStyle(color: Colors.white70),
                      ),
      ),
    );
  }

  Future<void> _showStarredUsersSheetQuick() async {
    try {
      final snap = await _database
          .child('users')
          .child('users')
          .child(widget.videoOwnerId)
          .child('videos')
          .child(widget.videoId)
          .get();
      if (!mounted) return;
      Map<String, dynamic>? video;
      if (snap.exists && snap.value is Map) {
        video = Map<String, dynamic>.from(snap.value as Map);
        video['id'] = widget.videoId;
      }

      final starUsersRaw = video != null ? video['star_users'] : null;
      Map<String, dynamic> starUsers = {};
      if (starUsersRaw != null) {
        if (starUsersRaw is Map) {
          starUsers = Map<String, dynamic>.from(starUsersRaw);
        } else if (starUsersRaw is List) {
          // Converte lista userId -> mappa {userId: true}
          for (final item in starUsersRaw) {
            if (item != null) starUsers[item.toString()] = true;
          }
        }
      }

      if (starUsers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No stars yet', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w500)),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Users who starred this post',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : Colors.black54,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withOpacity(0.8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${starUsers.length}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),

                    ],
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _getStarredUsersQuick(starUsers),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(child: Text('Error loading users', style: TextStyle(color: Colors.red)));
                    }
                    final users = snapshot.data ?? [];
                    if (users.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.star_outline, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No users found', style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        return _buildStarredUserItemQuick(user);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error loading stars')),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _getStarredUsersQuick(Map<String, dynamic> starUsers) async {
    final List<Map<String, dynamic>> users = [];
    for (final entry in starUsers.entries) {
      final String userId = entry.key.toString();
      try {
        final userSnapshot = await _database
            .child('users')
            .child('users')
            .child(userId)
            .child('profile')
            .get();
        if (userSnapshot.exists && userSnapshot.value is Map) {
          final userData = Map<String, dynamic>.from(userSnapshot.value as Map);
          users.add({
            'uid': userId,
            'displayName': userData['display_name'] ?? userData['displayName'] ?? 'Anonymous',
            'profileImage': userData['profileImageUrl'] ?? '',
            'username': userData['username'] ?? '',
          });
        } else {
          users.add({'uid': userId, 'displayName': 'Unknown User', 'profileImage': '', 'username': ''});
        }
      } catch (e) {
        users.add({'uid': userId, 'displayName': 'Unknown User', 'profileImage': '', 'username': ''});
      }
    }
    
    // Sort users to put highlighted star user first
    if (widget.highlightStarUserId != null) {
      users.sort((a, b) {
        if (a['uid'] == widget.highlightStarUserId) return -1;
        if (b['uid'] == widget.highlightStarUserId) return 1;
        return 0;
      });
    }
    
    return users;
  }



  Widget _buildStarredUserItemQuick(Map<String, dynamic> user) {
    final bool isHighlighted = widget.highlightStarUserId == user['uid'];
    
    final child = GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileEditPage(userId: user['uid']),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Colors.grey[800] 
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[300]!,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar utente
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[300],
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: user['profileImage'] != null && user['profileImage'].toString().isNotEmpty
                    ? Image.network(
                        user['profileImage'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFF667eea),
                                  Color(0xFF764ba2),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                transform: GradientRotation(135 * pi / 180),
                              ),
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 24,
                            ),
                          );
                        },
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF667eea),
                              Color(0xFF764ba2),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            transform: GradientRotation(135 * pi / 180),
                          ),
                        ),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Informazioni utente
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['displayName'] ?? 'Anonymous',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).textTheme.titleMedium?.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (user['username'] != null && user['username'].toString().isNotEmpty)
                    Text(
                      '@${user['username']}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            
            // Icona stella e freccia
            Row(
              mainAxisSize: MainAxisSize.min,
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
                      transform: GradientRotation(135 * pi / 180),
                    ).createShader(bounds);
                  },
                  child: const Icon(
                    Icons.star,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    
    // Se non è evidenziato, restituisci direttamente il child
    if (!isHighlighted) return child;
    
    // Altrimenti, applica l'animazione di evidenziazione come per i commenti
    return TweenAnimationBuilder<double>(
      key: ValueKey('highlight_star_' + user['uid'].toString()),
      tween: Tween(begin: 0.96, end: 1.0),
      duration: Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (context, scale, animatedChild) {
        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF6C63FF).withOpacity(0.25),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }
} 