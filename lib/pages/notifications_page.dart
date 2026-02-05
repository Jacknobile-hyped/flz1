import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter
import 'social/threads_page.dart';
import 'social/instagram_page.dart';
import 'social/facebook_page.dart';
import 'social/tiktok_page.dart';
import 'video_quick_view_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _expiringTokens = [];
  List<Map<String, dynamic>> _commentNotifications = [];
  List<Map<String, dynamic>> _starNotifications = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _isCommentsLoading = true;
  bool _isStarsLoading = true;


  // Stato: tendina commenti aperta
  bool _isCommentsSheetOpen = false;
  bool _isStarsSheetOpen = false;
  bool _showDeleteAllAction = false;
  bool _showDeleteAllStarsAction = false;
  
  // Stato per l'animazione di eliminazione
  bool _isDeletingComments = false;
  Set<String> _deletingCommentIds = {};
  Map<String, AnimationController> _commentSlideControllers = {};
  Map<String, Animation<Offset>> _commentSlideAnimations = {};
  
  // Stato per l'animazione di eliminazione delle star
  bool _isDeletingStars = false;
  Set<String> _deletingStarIds = {};
  Map<String, AnimationController> _starSlideControllers = {};
  Map<String, Animation<Offset>> _starSlideAnimations = {};

  // Stato filtro stars (all, video_star, comment_star, reply_star)
  String _selectedStarFilter = 'all';
  bool _showStarFilterDropdown = false;
  late AnimationController _starFilterAnimationController;
  late Animation<double> _starFilterAnimation;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _loadCommentNotifications();
    _loadStarNotifications();
    _checkExpiringTokens();
    
    // Initialize star filter dropdown animation
    _starFilterAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _starFilterAnimation = CurvedAnimation(
      parent: _starFilterAnimationController,
      curve: Curves.easeInOut,
    );
  }

  Future<void> _loadNotifications({bool manageLoadingState = true}) async {
    if (_currentUser == null) {
      if (manageLoadingState) setState(() => _isLoading = false);
      return;
    }

    try {
      final snapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('notifications')
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final notifications = data.entries.map((entry) {
          final notification = entry.value as Map<dynamic, dynamic>;
          return {
            'id': entry.key.toString(),
            'title': notification['title']?.toString() ?? '',
            'message': notification['message']?.toString() ?? '',
            'type': notification['type']?.toString() ?? 'info',
            'timestamp': notification['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
            'read': notification['read'] as bool? ?? false,
            'action_url': notification['action_url']?.toString(),
            'platform': notification['platform']?.toString(),
            'post_id': notification['post_id']?.toString(),
          };
        }).toList();

        // Sort by timestamp (newest first)
        notifications.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

        if (manageLoadingState) {
          setState(() {
            _notifications = notifications;
            _isLoading = false;
          });
        } else {
          setState(() {
            _notifications = notifications;
          });
        }
      } else {
        if (manageLoadingState) {
          setState(() {
            _notifications = [];
            _isLoading = false;
          });
        } else {
          setState(() {
            _notifications = [];
          });
        }
      }
    } catch (e) {
      print('Error loading notifications: $e');
      if (manageLoadingState) setState(() => _isLoading = false);
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

  Future<void> _loadCommentNotifications() async {
    if (_currentUser == null) {
      if (mounted) {
        setState(() {
          _isCommentsLoading = false;
        });
      }
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _isCommentsLoading = true;
        });
      }
      final snapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('notificationcomment')
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final comments = <Map<String, dynamic>>[];
        
        // Process each comment and load profile images
        for (final entry in data.entries) {
          final comment = entry.value as Map<dynamic, dynamic>;
          final userId = comment['userId']?.toString() ?? '';
          
          // Load profile image from the correct Firebase path
          String? profileImageUrl;
          if (userId.isNotEmpty) {
            profileImageUrl = await _loadUserProfileImage(userId);
          }
          
          comments.add({
            'id': entry.key.toString(),
            'text': comment['text']?.toString() ?? '',
            'userId': userId,
            'userDisplayName': comment['userDisplayName']?.toString() ?? 'Anonymous',
            'userProfileImage': profileImageUrl ?? '',
            'timestamp': comment['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
            'videoId': comment['videoId']?.toString() ?? '',
            'videoTitle': comment['videoTitle']?.toString() ?? 'Untitled Video',
            'videoOwnerId': comment['videoOwnerId']?.toString() ?? '',
            'type': comment['type']?.toString() ?? 'comment',
            'read': comment['read'] as bool? ?? false,
            'replies_count': comment['replies_count'] as int? ?? 0,
            'star_count': comment['star_count'] as int? ?? 0,
            'star_users': comment['star_users'] as Map<dynamic, dynamic>? ?? <String, dynamic>{},
          });
        }

        // Sort by timestamp (newest first)
        comments.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

        if (mounted) {
          setState(() {
            _commentNotifications = comments;
            _isCommentsLoading = false;
          });
        }
        
        // Le animazioni verranno inizializzate dinamicamente quando si costruiscono le card
      } else {
        if (mounted) {
          setState(() {
            _commentNotifications = [];
            _isCommentsLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading comment notifications: $e');
      if (mounted) {
        setState(() {
          _commentNotifications = [];
          _isCommentsLoading = false;
        });
      }
    }
  }

  Future<void> _loadStarNotifications() async {
    if (_currentUser == null) {
      if (mounted) {
        setState(() {
          _isStarsLoading = false;
        });
      }
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _isStarsLoading = true;
        });
      }
      final snapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('notificationstars')
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final stars = <Map<String, dynamic>>[];
        
        // Process each star notification and load profile images
        for (final entry in data.entries) {
          final star = entry.value as Map<dynamic, dynamic>;
          final starUserId = star['starUserId']?.toString() ?? '';
          
          // Load profile image from the correct Firebase path
          String? profileImageUrl;
          if (starUserId.isNotEmpty) {
            profileImageUrl = await _loadUserProfileImage(starUserId);
          }
          
          stars.add({
            'id': entry.key.toString(),
            'videoId': star['videoId']?.toString() ?? '',
            'videoTitle': star['videoTitle']?.toString() ?? 'Untitled Video',
            'videoOwnerId': star['videoOwnerId']?.toString() ?? '',
            'commentId': star['commentId']?.toString(),
            'replyId': star['replyId']?.toString(),
            'commentOwnerId': star['commentOwnerId']?.toString(),
            'replyOwnerId': star['replyOwnerId']?.toString(),
            'starUserId': starUserId,
            'starUserDisplayName': star['starUserDisplayName']?.toString() ?? 'Anonymous',
            'starUserProfileImage': profileImageUrl ?? '',
            'timestamp': star['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
            'type': star['type']?.toString() ?? 'video_star',
            'read': star['read'] as bool? ?? false,
          });
        }

        // Sort by timestamp (newest first)
        stars.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

        if (mounted) {
          setState(() {
            _starNotifications = stars;
            _isStarsLoading = false;
          });
        }
        
        // Inizializza le animazioni per le nuove star
        for (final star in stars) {
          _initializeStarSlideAnimation(star['id']);
        }
      } else {
        if (mounted) {
          setState(() {
            _starNotifications = [];
            _isStarsLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading star notifications: $e');
      if (mounted) {
        setState(() {
          _starNotifications = [];
          _isStarsLoading = false;
        });
      }
    }
  }

  Future<void> _checkExpiringTokens({bool manageLoadingState = true}) async {
    if (_currentUser == null) return;

    try {
      // Carica i dati utente dal path corretto
      final userId = _currentUser!.uid;
      final userRef = _database.child('users').child(userId);
      final userSnapshot = await userRef.get();
      Map<dynamic, dynamic> userData = {};
      if (userSnapshot.exists && userSnapshot.value is Map) {
        userData = userSnapshot.value as Map<dynamic, dynamic>;
      }

      // Carica anche i dati threads dal path users/users/{uid}/social_accounts/threads
      Map<dynamic, dynamic> threadsData = {};
      final threadsRef = _database.child('users').child('users').child(userId).child('social_accounts').child('threads');
      final threadsSnapshot = await threadsRef.get();
      if (threadsSnapshot.exists && threadsSnapshot.value is Map) {
        threadsData = threadsSnapshot.value as Map<dynamic, dynamic>;
      }

        final now = DateTime.now();
        final sixtyDaysFromNow = now.add(const Duration(days: 60));
        final expiringTokens = <Map<String, dynamic>>[];

      // Facebook
      if (userData.containsKey('facebook') && userData['facebook'] is Map) {
        final facebookData = userData['facebook'] as Map<dynamic, dynamic>;
        for (final entry in facebookData.entries) {
          final pageData = entry.value as Map<dynamic, dynamic>;
          if (pageData['created_at'] != null) {
            final createdAt = DateTime.fromMillisecondsSinceEpoch(pageData['created_at'] as int);
            final expiresAt = createdAt.add(const Duration(days: 60));
            final daysLeft = expiresAt.difference(now).inDays;
            if (daysLeft <= 5 && daysLeft >= 0) {
              expiringTokens.add({
                'platform': 'Facebook',
                'account_name': pageData['display_name'] ?? 'Unknown',
                'profile_image_url': pageData['profile_image_url'] ?? '',
                'expires_at': expiresAt,
                'days_left': daysLeft,
                'account_id': entry.key.toString(),
              });
            }
          }
        }
      }

      // Instagram
      if (userData.containsKey('instagram') && userData['instagram'] is Map) {
        final instagramData = userData['instagram'] as Map<dynamic, dynamic>;
        for (final entry in instagramData.entries) {
          final accountData = entry.value as Map<dynamic, dynamic>;
          final now = DateTime.now();
          final sixtyDaysFromNow = now.add(const Duration(days: 60));
          // Basic access: instagram_connected_at
          if (accountData['instagram_connected_at'] != null && accountData['token_expires_in'] != null) {
            final instagramConnectedAt = DateTime.fromMillisecondsSinceEpoch(accountData['instagram_connected_at'] as int);
            final tokenExpiresIn = accountData['token_expires_in'] as int;
            final expiresAt = instagramConnectedAt.add(Duration(seconds: tokenExpiresIn));
            final daysLeft = expiresAt.difference(now).inDays;
            if (daysLeft <= 5 && daysLeft >= 0) {
              expiringTokens.add({
                'platform': 'Instagram',
                'account_name': accountData['display_name'] ?? 'Unknown',
                'profile_image_url': accountData['profile_image_url'] ?? '',
                'expires_at': expiresAt,
                'days_left': daysLeft,
                'account_id': entry.key.toString(),
                'access_type': 'basic',
              });
            }
          }
          // Advanced access: facebook_connected_at
          if (accountData['facebook_connected_at'] != null) {
            final facebookConnectedAt = DateTime.fromMillisecondsSinceEpoch(accountData['facebook_connected_at'] as int);
            final expiresAt = facebookConnectedAt.add(const Duration(days: 60));
            final daysLeft = expiresAt.difference(now).inDays;
            if (daysLeft <= 5 && daysLeft >= 0) {
              expiringTokens.add({
                'platform': 'Instagram',
                'account_name': accountData['display_name'] ?? 'Unknown',
                'profile_image_url': accountData['profile_image_url'] ?? '',
                'expires_at': expiresAt,
                'days_left': daysLeft,
                'account_id': entry.key.toString(),
                'access_type': 'advanced',
              });
            }
          }
        }
      }

      // TikTok
      Map<dynamic, dynamic> tiktokData = {};
      final tiktokRef = _database.child('users').child(userId).child('tiktok');
      final tiktokSnapshot = await tiktokRef.get();
      if (tiktokSnapshot.exists && tiktokSnapshot.value is Map) {
        tiktokData = tiktokSnapshot.value as Map<dynamic, dynamic>;
      }
      if (tiktokData.isNotEmpty) {
        for (final entry in tiktokData.entries) {
            final accountData = entry.value as Map<dynamic, dynamic>;
          if (accountData['created_at'] != null) {
            final createdAt = DateTime.fromMillisecondsSinceEpoch(accountData['created_at'] as int);
            final expiresAt = createdAt.add(const Duration(days: 60));
            final daysLeft = expiresAt.difference(now).inDays;
            if (daysLeft <= 5 && daysLeft >= 0) {
              expiringTokens.add({
                'platform': 'TikTok',
                'account_name': accountData['display_name'] ?? 'Unknown',
                'profile_image_url': accountData['profile_image_url'] ?? '',
                'expires_at': expiresAt,
                'days_left': daysLeft,
                'account_id': entry.key.toString(),
              });
            }
          }
        }
      }

      // Threads (solo da social_accounts)
      for (final entry in threadsData.entries) {
            final accountData = entry.value as Map<dynamic, dynamic>;
        if (accountData['created_at'] != null) {
          final createdAt = DateTime.fromMillisecondsSinceEpoch(accountData['created_at'] as int);
          final expiresAt = createdAt.add(const Duration(days: 60));
          final daysLeft = expiresAt.difference(now).inDays;
          if (daysLeft <= 5 && daysLeft >= 0) {
            expiringTokens.add({
              'platform': 'Threads',
              'account_name': accountData['display_name'] ?? 'Unknown',
              'profile_image_url': accountData['profile_image_url'] ?? '',
              'expires_at': expiresAt,
              'days_left': daysLeft,
              'account_id': entry.key.toString(),
            });
          }
        }
      }

        setState(() {
          _expiringTokens = expiringTokens;
        });
    } catch (e) {
      print('Error checking expiring tokens: $e');
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    if (_currentUser == null) return;

    try {
      await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('notifications')
          .child(notificationId)
          .child('read')
          .set(true);

      setState(() {
        final index = _notifications.indexWhere((n) => n['id'] == notificationId);
        if (index != -1) {
          _notifications[index]['read'] = true;
        }
      });
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  Future<void> _markCommentAsRead(String commentId) async {
    if (_currentUser == null) return;

    try {
      await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('notificationcomment')
          .child(commentId)
          .child('read')
          .set(true);

      setState(() {
        final index = _commentNotifications.indexWhere((c) => c['id'] == commentId);
        if (index != -1) {
          _commentNotifications[index]['read'] = true;
        }
      });
    } catch (e) {
      print('Error marking comment as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    if (_currentUser == null) return;

    try {
      final batch = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('notifications');

      for (final notification in _notifications) {
        if (!notification['read']) {
          await batch.child(notification['id']).child('read').set(true);
        }
      }

      setState(() {
        for (final notification in _notifications) {
          notification['read'] = true;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All notifications marked as read'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error marking all notifications as read: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error marking notifications as read'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    if (_currentUser == null) return;

    try {
      await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('notifications')
          .child(notificationId)
          .remove();

      setState(() {
        _notifications.removeWhere((n) => n['id'] == notificationId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification deleted'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error deleting notification: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error deleting notification'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteCommentNotification(String commentId) async {
    if (_currentUser == null) return;

    try {
      // Inizializza l'animazione di scorrimento se non esiste
      _initializeCommentSlideAnimation(commentId);
      
      // Avvia l'animazione di scorrimento
      await _commentSlideControllers[commentId]!.forward();
      
      // Aspetta che l'animazione finisca
      await Future.delayed(Duration(milliseconds: 300));
      
      // Aggiorna lo stato locale per rimuovere il commento
      setState(() {
        _commentNotifications.removeWhere((c) => c['id'] == commentId);
      });

      // Poi elimina dal database
      await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('notificationcomment')
          .child(commentId)
          .remove();

      print('Comment notification deleted successfully: $commentId');
    } catch (e) {
      print('Error deleting comment notification: $e');
      
      // Se c'è un errore, ripristina il commento nella lista
      // (qui dovresti ricaricare il commento dal database)
      _loadCommentNotifications();
      
      // Feedback di errore rimosso - solo log di debug
    }
  }

  Future<void> _markStarAsRead(String starId) async {
    if (_currentUser == null) return;

    try {
      await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('notificationstars')
          .child(starId)
          .child('read')
          .set(true);

      setState(() {
        final index = _starNotifications.indexWhere((s) => s['id'] == starId);
        if (index != -1) {
          _starNotifications[index]['read'] = true;
        }
      });
    } catch (e) {
      print('Error marking star as read: $e');
    }
  }

  Future<void> _deleteStarNotification(String starId) async {
    if (_currentUser == null) return;

    try {
      // Inizializza l'animazione di scorrimento se non esiste
      _initializeStarSlideAnimation(starId);
      
      // Avvia l'animazione di scorrimento
      await _starSlideControllers[starId]!.forward();
      
      // Aspetta che l'animazione finisca
      await Future.delayed(Duration(milliseconds: 300));
      
      // Aggiorna lo stato locale per rimuovere la star
      setState(() {
        _starNotifications.removeWhere((s) => s['id'] == starId);
      });

      // Poi elimina dal database
      await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('notificationstars')
          .child(starId)
          .remove();

      print('Star notification deleted successfully: $starId');
    } catch (e) {
      print('Error deleting star notification: $e');
      
      // Se c'è un errore, ripristina la star nella lista
      _loadStarNotifications();
      
      // Feedback di errore rimosso - solo log di debug
    }
  }







  void _initializeCommentSlideAnimation(String commentId) {
    if (!_commentSlideControllers.containsKey(commentId)) {
      final controller = AnimationController(
        duration: Duration(milliseconds: 400),
        vsync: this,
      );
      
      final slideAnimation = Tween<Offset>(
        begin: Offset.zero,
        end: Offset(1.0, 0.0), // Scorre verso destra
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOutCubic,
      ));
      
      _commentSlideControllers[commentId] = controller;
      _commentSlideAnimations[commentId] = slideAnimation;
    }
  }

  void _resetCommentSlideAnimation(String commentId) {
    if (_commentSlideControllers.containsKey(commentId)) {
      _commentSlideControllers[commentId]!.reset();
    }
  }

  void _initializeStarSlideAnimation(String starId) {
    if (!_starSlideControllers.containsKey(starId)) {
      final controller = AnimationController(
        duration: Duration(milliseconds: 400),
        vsync: this,
      );
      
      final slideAnimation = Tween<Offset>(
        begin: Offset.zero,
        end: Offset(1.0, 0.0), // Scorre verso destra
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOutCubic,
      ));
      
      _starSlideControllers[starId] = controller;
      _starSlideAnimations[starId] = slideAnimation;
    }
  }

  void _resetStarSlideAnimation(String starId) {
    if (_starSlideControllers.containsKey(starId)) {
      _starSlideControllers[starId]!.reset();
    }
  }



  @override
  void dispose() {
    // Dispose comment slide controllers
    for (final controller in _commentSlideControllers.values) {
      controller.dispose();
    }
    _commentSlideControllers.clear();
    _commentSlideAnimations.clear();
    
    // Dispose star slide controllers
    for (final controller in _starSlideControllers.values) {
      controller.dispose();
    }
    _starSlideControllers.clear();
    _starSlideAnimations.clear();
    
    _starFilterAnimationController.dispose();
    super.dispose();
  }

  void _showReplyDialog(Map<String, dynamic> comment) {
    final TextEditingController replyController = TextEditingController();
    final FocusNode replyFocusNode = FocusNode();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Color(0xFF1E1E1E) 
                : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Container(
                height: 60,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Center(
                  child: Text(
                      'Reply to comment',
                      style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                        color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white70 
                          : Colors.black54,
                    ),
                  ),
                ),
              ),
              
              // Original comment preview
              Container(
                margin: EdgeInsets.symmetric(horizontal: 20),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.grey[800] 
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Color(0xFF6C63FF).withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: ClipOval(
                            child: comment['userProfileImage']?.isNotEmpty == true
                                ? Image.network(
                                    comment['userProfileImage'],
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Icon(
                                      Icons.person,
                                      color: Color(0xFF6C63FF),
                                      size: 12,
                                    ),
                                  )
                                : Icon(
                                    Icons.person,
                                    color: Color(0xFF6C63FF),
                                    size: 12,
                                  ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          comment['userDisplayName'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white 
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      comment['text'],
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.white70 
                            : Colors.black87,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 16),
              
              // Reply input area
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      TextField(
                        controller: replyController,
                        focusNode: replyFocusNode,
                        maxLines: null, // Permette infinite righe
                        textInputAction: TextInputAction.newline, // Cambia il tasto invio in "a capo"
                        keyboardType: TextInputType.multiline, // Abilita la tastiera multilinea
                        decoration: InputDecoration(
                          hintText: 'Write your reply...',
                          hintStyle: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.withOpacity(0.3),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.withOpacity(0.3),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Color(0xFF6C63FF),
                              width: 2,
                            ),
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical:12),
                          filled: true,
                          fillColor: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey[800] 
                              : Colors.grey[50],
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.white 
                              : Colors.black87,
                        ),
                      ),
                      SizedBox(height: 16),
                      
                      // Reply button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (replyController.text.trim().isNotEmpty) {
                              Navigator.of(context).pop();
                              await _submitReply(comment, replyController.text.trim());
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF6C63FF),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Reply',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Bottom padding for keyboard
              SizedBox(height: 20),
            ],
          ),
        );
      },
    ).then((_) {
      replyController.dispose();
      replyFocusNode.dispose();
    });
    
    // Auto focus after a short delay to show keyboard
    Future.delayed(Duration(milliseconds: 300), () {
      replyFocusNode.requestFocus();
    });
  }

  Future<void> _submitReply(Map<String, dynamic> comment, String replyText) async {
    if (_currentUser == null) return;

    try {
      final commentId = comment['id'] as String;
      final videoId = comment['videoId'] as String;
      final videoUserId = comment['videoOwnerId'] as String;
      final currentUserId = _currentUser!.uid;
      final currentUserDisplayName = _currentUser!.displayName ?? 'Anonymous';
      final currentUserProfileImage = _currentUser!.photoURL ?? '';
      
      // Genera ID univoco per la risposta
      final replyId = _database.child('replies').push().key!;
      
      // Percorso per la risposta
      final replyRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(commentId)
          .child('replies')
          .child(replyId);
      
      // Dati della risposta
      final replyData = {
        'id': replyId,
        'text': replyText,
        'userId': currentUserId,
        'userDisplayName': currentUserDisplayName,
        'userProfileImage': currentUserProfileImage,
        'timestamp': ServerValue.timestamp,
        'videoId': videoId,
        'parentCommentId': commentId,
        'replies_count': 0,
        'star_count': 0,
        'star_users': {},
      };
      
      // Salva la risposta nel database
      await replyRef.set(replyData);
      
      // Aggiorna il conteggio delle risposte nel commento
      final commentRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(commentId);
      
      final repliesCountSnapshot = await commentRef.child('replies_count').get();
      int currentRepliesCount = 0;
      
      if (repliesCountSnapshot.exists) {
        final value = repliesCountSnapshot.value;
        if (value is int) {
          currentRepliesCount = value;
        } else if (value != null) {
          currentRepliesCount = int.tryParse(value.toString()) ?? 0;
        }
      }
      
      await commentRef.child('replies_count').set(currentRepliesCount + 1);
      
      // Salva la risposta nella cartella notificationcomment del proprietario del commento
      final commentOwnerId = comment['userId'] as String?;
      if (commentOwnerId != null && currentUserId != commentOwnerId) {
        final notificationReplyRef = _database
            .child('users')
            .child('users')
            .child(commentOwnerId)
            .child('notificationcomment')
            .child('${commentId}_reply_${replyId}');
        
        // Dati della risposta per le notifiche
        final notificationReplyData = {
          'id': '${commentId}_reply_${replyId}',
          'text': replyText,
          'userId': currentUserId,
          'userDisplayName': currentUserDisplayName,
          'userProfileImage': currentUserProfileImage,
          'timestamp': ServerValue.timestamp,
          'videoId': videoId,
          'videoTitle': comment['videoTitle'] ?? 'Untitled Video',
          'videoOwnerId': videoUserId,
          'parentCommentId': commentId,
          'type': 'reply',
          'read': false, // Marca come non letto
          'replies_count': 0,
          'star_count': 0,
          'star_users': {},
        };
        
        await notificationReplyRef.set(notificationReplyData);
        print('Risposta salvata in notificationcomment per l\'utente $commentOwnerId');
      }
      
      // Aggiorna lo stato locale
      setState(() {
        if (comment.containsKey('replies_count')) {
          comment['replies_count'] = (comment['replies_count'] ?? 0) + 1;
        }
      });
      
      print('Risposta salvata per il commento $commentId');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reply posted!'),
          backgroundColor: Color(0xFF6C63FF),
          duration: Duration(seconds: 2),
        ),
      );
      
    } catch (e) {
      print('Errore nel salvataggio della risposta: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error posting reply'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _refreshAllData() async {
    // Non mostrare il cerchio di caricamento per il refresh manuale
    // setState(() { _isLoading = true; });
    try {
      // Carica sia le notifiche che gli avvisi di token in scadenza, commenti e stelle
      await Future.wait([
        _loadNotifications(manageLoadingState: false),
        _loadCommentNotifications(),
        _loadStarNotifications(),
        _checkExpiringTokens(manageLoadingState: false),
      ]);
      
      // Pulisci le animazioni dopo il refresh
      _deletingCommentIds.clear();
      _isDeletingComments = false;
      _deletingStarIds.clear();
      _isDeletingStars = false;
      _showDeleteAllAction = false;
      _showDeleteAllStarsAction = false;
    } catch (e) {
      print('Error refreshing data: $e');
    } finally {
      // Non settare _isLoading a false qui, lasciamo la UI invariata
      // setState(() { _isLoading = false; });
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type.toLowerCase()) {
      case 'success':
        return Icons.check_circle;
      case 'error':
        return Icons.error;
      case 'warning':
        return Icons.warning;
      case 'upload':
        return Icons.cloud_upload;
      case 'schedule':
        return Icons.schedule;
      case 'analytics':
        return Icons.analytics;
      case 'engagement':
        return Icons.trending_up;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type.toLowerCase()) {
      case 'success':
        return Colors.green;
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'upload':
        return Colors.blue;
      case 'schedule':
        return Colors.purple;
      case 'analytics':
        return Colors.indigo;
      case 'engagement':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'facebook':
        return Icons.facebook;
      case 'instagram':
        return Icons.camera_alt;
      case 'threads':
        return Icons.forum;
      case 'tiktok':
        return Icons.video_library;
      default:
        return Icons.account_circle;
    }
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'facebook':
        return const Color(0xFF1877F2); // Facebook blue
      case 'instagram':
        return const Color(0xFFC13584); // Instagram purple
      case 'threads':
        return Colors.black; // Threads black
      case 'tiktok':
        return const Color(0xFF00F2EA); // TikTok turchese
      default:
        return Colors.grey;
    }
  }

  String _getPlatformLogo(String platform) {
    switch (platform.toLowerCase()) {
      case 'facebook':
        return 'assets/loghi/logo_facebook.png';
      case 'instagram':
        return 'assets/loghi/logo_insta.png';
      case 'threads':
        return 'assets/loghi/threads_logo.png';
      case 'tiktok':
        return 'assets/loghi/logo_tiktok.png';
      default:
        return 'assets/loghi/logo_facebook.png'; // fallback
    }
  }

  Widget _buildPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'facebook':
      case 'instagram':
      case 'threads':
      case 'tiktok':
        return Image.asset(
          _getPlatformLogo(platform),
          width: 40,
          height: 40,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                _getPlatformIcon(platform),
            color: _getPlatformColor(platform),
            size: 32,
          ),
        );
      default:
        return Image.asset(
          _getPlatformLogo(platform),
          width: 40,
          height: 40,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                _getPlatformIcon(platform),
                color: _getPlatformColor(platform),
            size: 32,
          ),
        );
    }
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
                          Color(0xFF667eea),
                          Color(0xFF764ba2),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180),
                      ).createShader(bounds);
                    },
                    child: Text(
                      'Fluxar',
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
                      'Notifications',
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

  Widget _buildNotificationCard(Map<String, dynamic> notification, ThemeData theme) {
    final isRead = notification['read'] as bool;
    final type = notification['type'] as String;
    final title = notification['title'] as String;
    final message = notification['message'] as String;
    final timestamp = notification['timestamp'] as int;
    final platform = notification['platform'] as String?;

    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(dateTime);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: isRead ? 1 : 3,
      color: isRead 
          ? (theme.brightness == Brightness.dark ? Color(0xFF1E1E1E).withOpacity(0.8) : Colors.grey[50])
          : theme.cardColor,
      shadowColor: theme.brightness == Brightness.dark ? Colors.black : Colors.black.withOpacity(0.1),
      child: InkWell(
        onTap: () {
          if (!isRead) {
            _markAsRead(notification['id']);
          }
          // Handle notification action if needed
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isRead 
                ? Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.1),
                    width: 1,
                  )
                : Border.all(
                    color: _getNotificationColor(type).withOpacity(0.3),
                    width: 1.5,
                  ),
            gradient: isRead 
                ? null 
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _getNotificationColor(type).withOpacity(0.05),
                      _getNotificationColor(type).withOpacity(0.02),
                    ],
                  ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Notification icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getNotificationColor(type).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getNotificationColor(type).withOpacity(0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _getNotificationColor(type).withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  _getNotificationIcon(type),
                  color: _getNotificationColor(type),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              
              // Notification content
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
                              fontSize: 16,
                              fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                              color: isRead 
                                  ? theme.colorScheme.onSurface.withOpacity(0.7)
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _getNotificationColor(type),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _getNotificationColor(type).withOpacity(0.3),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formattedDate,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (platform != null && platform.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Icon(
                            Icons.public,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            platform,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              
              // Action menu
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'mark_read':
                      if (!isRead) {
                        _markAsRead(notification['id']);
                      }
                      break;
                    case 'delete':
                      _deleteNotification(notification['id']);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (!isRead)
                    PopupMenuItem(
                      value: 'mark_read',
                      child: Row(
                        children: [
                          Icon(Icons.done, size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Mark as read', style: TextStyle(color: theme.colorScheme.onSurface)),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        const SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
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

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 80),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.2),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              Icons.notifications_none,
              size: 60,
              color: theme.colorScheme.primary.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No notifications yet',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
          ),

        ],
      ),
    );
  }

  Widget _buildTokenExpiryWarning() {
    if (_expiringTokens.isEmpty) return const SizedBox.shrink();
    
    return Column(
      children: _expiringTokens.map((token) => _buildSingleTokenWarning(token)).toList(),
    );
  }

  Widget _buildSingleTokenWarning(Map<String, dynamic> token) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final int daysLeft = (token['days_left'] is int) ? token['days_left'] : 0;
    final bool isUrgent = daysLeft <= 1;
    final String? accessType = token['access_type'] as String?;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        // Effetto vetro semi-trasparente opaco
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        // Bordo con effetto vetro più sottile
        border: Border.all(
          color: isUrgent 
              ? Colors.red.withOpacity(0.3)
              : Colors.grey.withOpacity(0.3),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (token['platform'] == 'Instagram') {
              if (accessType == 'basic') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => InstagramPage(autoConnectType: 'basic'),
                  ),
                );
              } else if (accessType == 'advanced') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => InstagramPage(autoConnectType: 'advanced'),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => InstagramPage(),
                  ),
                );
              }
            } else if (token['platform'] == 'Threads') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ThreadsPage(autoConnect: true),
                ),
              );
            } else if (token['platform'] == 'Facebook') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const FacebookPage(autoConnect: true),
                ),
              );
            } else if (token['platform'] == 'TikTok') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TikTokPage(autoConnect: true),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Redirecting to account management...'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with platform icon and urgency badge
                Row(
                  children: [
                    // Platform icon with background
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        // Icona con effetto vetro semi-trasparente
                        color: isDark 
                            ? Colors.white.withOpacity(0.2)
                            : Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
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
                      child: _buildPlatformIcon(token['platform']),
                    ),
                    const SizedBox(width: 16),
                    
                    // Main content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            token['platform'] == 'Instagram'
                              ? (accessType == 'basic'
                                  ? 'Basic access expires soon'
                                  : accessType == 'advanced'
                                    ? 'Advanced access expires soon'
                                    : '${token['platform']} token expires soon')
                              : '${token['platform']} token expires soon',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            token['platform'] == 'Instagram'
                              ? (accessType == 'basic'
                                  ? '${token['account_name']} needs Instagram login'
                                  : accessType == 'advanced'
                                    ? '${token['account_name']} needs Facebook login'
                                    : '${token['account_name']} needs reconnection')
                              : '${token['account_name']} needs reconnection',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Urgency badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isUrgent 
                            ? Colors.red.withOpacity(0.2)
                            : Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isUrgent 
                              ? Colors.red.withOpacity(0.4)
                              : Colors.grey.withOpacity(0.4),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isUrgent 
                                ? Colors.red.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isUrgent 
                                ? Icons.priority_high
                                : Icons.access_time,
                            size: 12,
                            color: isUrgent 
                                ? Colors.red.shade700
                                : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isUrgent
                                ? 'URGENT'
                                : (daysLeft >= 0 ? '$daysLeft days' : ''),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isUrgent
                                  ? Colors.red.shade700
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Account details row
                Row(
                  children: [
                    // Account profile image
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _getPlatformColor(token['platform']),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _getPlatformColor(token['platform']).withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: token['profile_image_url']?.isNotEmpty == true
                            ? Image.network(
                                token['profile_image_url'],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Icon(
                                  Icons.person,
                                  color: _getPlatformColor(token['platform']),
                                  size: 20,
                                ),
                              )
                            : Icon(
                                Icons.person,
                                color: _getPlatformColor(token['platform']),
                                size: 20,
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // Account info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            token['account_name'],
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Tap to reconnect text
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      ),
                      child: Text(
                        token['platform'] == 'Instagram'
                          ? (accessType == 'basic'
                              ? 'Tap to reconnect'
                              : accessType == 'advanced'
                                ? 'Tap to reconnect'
                                : 'Tap to reconnect')
                          : 'Tap to reconnect',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
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

  Widget _buildPasswordChangeInfoBox() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        crossAxisAlignment: CrossAxisAlignment.center,
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
            child: Icon(
              Icons.info_outline,
              size: 22,
              color: isDark ? Color(0xFF6C63FF) : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              'If you change the password of any connected account after connecting it, you must reconnect the account to continue using all features.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.4,
                fontWeight: FontWeight.w500,
                fontSize: 12.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStarsCard() {
    final theme = Theme.of(context);
    final unreadStars = _starNotifications.where((s) => !s['read']).length;
    final videoStars = _starNotifications.where((s) => s['type'] == 'video_star').length;
    final commentStars = _starNotifications.where((s) => s['type'] == 'comment_star').length;
    final replyStars = _starNotifications.where((s) => s['type'] == 'reply_star').length;
    
    if (_isStarsLoading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
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
        child: Center(
          child: Lottie.asset(
            'assets/animations/MainScene.json',
            width: 120,
            height: 120,
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        // Effetto vetro semi-trasparente opaco
        color: theme.brightness == Brightness.dark
            ? Colors.white.withOpacity(0.15)
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(16),
        // Bordo con effetto vetro più sottile
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.4),
          width: 1,
        ),
        // Ombra per effetto profondità e vetro
        boxShadow: [
          BoxShadow(
            color: theme.brightness == Brightness.dark
                ? Colors.black.withOpacity(0.4)
                : Colors.black.withOpacity(0.15),
            blurRadius: theme.brightness == Brightness.dark ? 25 : 20,
            spreadRadius: theme.brightness == Brightness.dark ? 1 : 0,
            offset: const Offset(0, 10),
          ),
          // Ombra interna per effetto vetro
          BoxShadow(
            color: theme.brightness == Brightness.dark
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showStarsSheet(),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Star icon with background
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.amber.withOpacity(0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
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
                      ).createShader(bounds);
                    },
                  child: Icon(
                    Icons.star,
                      color: Colors.white,
                    size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stars',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_starNotifications.length} star${_starNotifications.length == 1 ? '' : 's'} received',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_starNotifications.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (videoStars > 0) ...[
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Color(0xFF6C63FF).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$videoStars video${videoStars == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF6C63FF),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                            ],
                            if (commentStars > 0) ...[
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$commentStars comment${commentStars == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                            ],
                            if (replyStars > 0)
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$replyStars reply${replyStars == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Unread badge
                if (unreadStars > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      '$unreadStars',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                
                // Arrow icon
                Icon(
                  Icons.arrow_forward_ios,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommentsCard() {
    final theme = Theme.of(context);
    final unreadComments = _commentNotifications.where((c) => !c['read']).length;
    
    if (_isCommentsLoading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
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
        child: Center(
          child: Lottie.asset(
            'assets/animations/MainScene.json',
            width: 120,
            height: 120,
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        // Effetto vetro semi-trasparente opaco
        color: theme.brightness == Brightness.dark
            ? Colors.white.withOpacity(0.15)
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(16),
        // Bordo con effetto vetro più sottile
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.4),
          width: 1,
        ),
        // Ombra per effetto profondità e vetro
        boxShadow: [
          BoxShadow(
            color: theme.brightness == Brightness.dark
                ? Colors.black.withOpacity(0.4)
                : Colors.black.withOpacity(0.15),
            blurRadius: theme.brightness == Brightness.dark ? 25 : 20,
            spreadRadius: theme.brightness == Brightness.dark ? 1 : 0,
            offset: const Offset(0, 10),
          ),
          // Ombra interna per effetto vetro
          BoxShadow(
            color: theme.brightness == Brightness.dark
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showCommentsSheet(),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Comment icon with background
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    // Icona con effetto vetro semi-trasparente
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
                            ? Colors.black.withOpacity(0.2)
                            : Colors.black.withOpacity(0.1),
                        blurRadius: 5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.comment,
                    color: theme.brightness == Brightness.dark ? Color(0xFF6C63FF) : Color(0xFF6C63FF),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Comments',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_commentNotifications.length} comment${_commentNotifications.length == 1 ? '' : 's'} received',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Unread badge
                if (unreadComments > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Color(0xFF6C63FF),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF6C63FF).withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      '$unreadComments',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                
                // Arrow icon
                Icon(
                  Icons.arrow_forward_ios,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showStarsSheet() {
    setState(() => _isStarsSheetOpen = true);
    
    // Resetta tutte le animazioni di scorrimento quando si apre la tendina
    for (final star in _starNotifications) {
      _resetStarSlideAnimation(star['id']);
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : Colors.white,
      barrierColor: Colors.black.withOpacity(0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Color(0xFF1E1E1E) 
              : Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Container(
              height: 60,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Stack(
                children: [
                  // Titolo centrato
                  Center(
                    child: Text(
                      'Stars Received (${_starNotifications.length})',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.white70 
                            : Colors.black54,
                      ),
                    ),
                  ),
                  // Pulsante delete all a destra
                  if (_starNotifications.isNotEmpty)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
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
                          child: _showDeleteAllStarsAction
                              ? TextButton(
                                  key: ValueKey('delete_all_stars_text'),
                                  onPressed: () async {
                                    await _clearFilteredStarNotifications();
                                    setModalState(() {});
                                  },
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size(32, 32),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Delete',
                                    style: TextStyle(
                                      color: Colors.red[600],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  key: ValueKey('delete_all_stars_icon'),
                                  onPressed: () {
                                    setState(() => _showDeleteAllStarsAction = true);
                                    setModalState(() {});
                                  },
                                  icon: Icon(
                                    Icons.clear_all,
                                    size: 20,
                                    color: Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.white70 
                                        : Colors.black54,
                                  ),
                                  tooltip: 'Clear all stars',
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
                        // Filter dropdown
            Container(
              margin: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.08),
                  width: 1.2,
                ),
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: () {
                      setModalState(() {
                        _showStarFilterDropdown = !_showStarFilterDropdown;
                        if (_showStarFilterDropdown) {
                          _starFilterAnimationController.forward();
                        } else {
                          _starFilterAnimationController.reverse();
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
                              _getStarFilterIcon(_selectedStarFilter),
                              SizedBox(width: 12),
                              Text(
                                _getStarFilterLabel(_selectedStarFilter),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).textTheme.titleLarge?.color,
                                ),
                              ),
                            ],
                          ),
                          AnimatedIcon(
                            icon: AnimatedIcons.menu_close,
                            progress: _starFilterAnimation,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizeTransition(
                    sizeFactor: _starFilterAnimation,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(context).colorScheme.outline.withOpacity(0.08),
                            width: 1.2,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildStarFilterOption('all', 'All', Icons.star, Theme.of(context).colorScheme.primary, setModalState),
                          _buildStarFilterOption('video_star', 'Videos', Icons.video_library, Color(0xFF6C63FF), setModalState),
                          _buildStarFilterOption('comment_star', 'Comments', Icons.comment, Colors.green, setModalState),
                          _buildStarFilterOption('reply_star', 'Replies', Icons.reply, Colors.orange, setModalState),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 16),
            
            // Stars list
            Expanded(
              child: _isStarsLoading
                  ? Center(
                      child: Lottie.asset(
                        'assets/animations/MainScene.json',
                        width: 160,
                        height: 160,
                        fit: BoxFit.contain,
                      ),
                    )
                  : _getFilteredStars().isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.star_outline,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No stars yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Stars on your content will appear here',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _getFilteredStars().length,
                          itemBuilder: (context, index) {
                            final star = _getFilteredStars()[index];
                            return _buildStarCardWithAnimation(star);
                          },
                        ),
            ),
          ],
        ),
      );
    },
      ),
    ).whenComplete(() {
      if (mounted) {
        setState(() => _isStarsSheetOpen = false);
        
        // Pulisci le animazioni quando si chiude la tendina
        _deletingStarIds.clear();
        _isDeletingStars = false;
        _showDeleteAllAction = false;
      }
    });
  }

  Widget _buildFilterTab(String label, int count, String? filterType) {
    final theme = Theme.of(context);
    final isSelected = filterType == null || _starNotifications.any((s) => s['type'] == filterType);
    
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: isSelected 
            ? (filterType == 'video_star' ? Color(0xFF6C63FF).withOpacity(0.1)
               : filterType == 'comment_star' ? Colors.green.withOpacity(0.1)
               : filterType == 'reply_star' ? Colors.orange.withOpacity(0.1)
               : Colors.amber.withOpacity(0.1))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected 
              ? (filterType == 'video_star' ? Color(0xFF6C63FF)
                 : filterType == 'comment_star' ? Colors.green
                 : filterType == 'reply_star' ? Colors.orange
                 : Colors.amber)
              : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isSelected 
                  ? (filterType == 'video_star' ? Color(0xFF6C63FF)
                     : filterType == 'comment_star' ? Colors.green
                     : filterType == 'reply_star' ? Colors.orange
                     : Colors.amber)
                  : Colors.grey[600],
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isSelected 
                  ? (filterType == 'video_star' ? Color(0xFF6C63FF)
                     : filterType == 'comment_star' ? Colors.green
                     : filterType == 'reply_star' ? Colors.orange
                     : Colors.amber)
                  : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStarCard(Map<String, dynamic> star) {
    final theme = Theme.of(context);
    final isRead = star['read'] as bool;
    final timestamp = star['timestamp'] as int;
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
    final type = star['type'] as String;
    
    // Get content info based on type
    String contentTitle = '';
    String contentType = '';
    Color typeColor = Colors.amber;
    
    switch (type) {
      case 'video_star':
        contentTitle = star['videoTitle'] ?? 'Untitled Video';
        contentType = 'video';
        typeColor = Color(0xFF6C63FF);
        break;
      case 'comment_star':
        contentTitle = 'Comment on "${star['videoTitle'] ?? 'Untitled Video'}"';
        contentType = 'comment';
        typeColor = Colors.green;
        break;
      case 'reply_star':
        contentTitle = 'Reply on "${star['videoTitle'] ?? 'Untitled Video'}"';
        contentType = 'reply';
        typeColor = Colors.orange;
        break;
    }
    
    return Dismissible(
      key: Key(star['id'] as String),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.red.shade400,
              Colors.red.shade600,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.3),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
          ],
        ),
      ),
      confirmDismiss: (direction) async => true,
      onDismissed: (direction) {
        _deleteStarNotification(star['id'] as String);
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          // Effetto vetro semi-trasparente opaco
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.12)
              : Colors.white.withOpacity(0.22),
          borderRadius: BorderRadius.circular(12),
          // Bordo con effetto vetro più sottile
          border: Border.all(
            color: theme.brightness == Brightness.dark
                ? Colors.white.withOpacity(0.2)
                : Colors.white.withOpacity(0.35),
            width: 1,
          ),
          // Ombra per effetto profondità e vetro
          boxShadow: [
            BoxShadow(
              color: theme.brightness == Brightness.dark
                  ? Colors.black.withOpacity(0.35)
                  : Colors.black.withOpacity(0.12),
              blurRadius: theme.brightness == Brightness.dark ? 22 : 18,
              spreadRadius: theme.brightness == Brightness.dark ? 1 : 0,
              offset: const Offset(0, 8),
            ),
            // Ombra interna per effetto vetro
            BoxShadow(
              color: theme.brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.white.withOpacity(0.5),
              blurRadius: 2,
              spreadRadius: -2,
              offset: const Offset(0, 2),
            ),
          ],
          // Gradiente più sottile per effetto vetro
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: theme.brightness == Brightness.dark
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
        child: InkWell(
          onTap: () {
            if (!isRead) {
              _markStarAsRead(star['id']);
            }
            String videoId = (star['videoId'] ?? '').toString();
            if (videoId.isEmpty) {
              videoId = (star['video_id'] ?? '').toString();
            }
            if (videoId.isEmpty) {
              videoId = (star['post_id'] ?? '').toString();
            }
            // Fallback robusto per owner ID in caso di dati storici mancanti
            String videoOwnerId = (star['videoOwnerId'] ?? '').toString();
            if (videoOwnerId.isEmpty) {
              videoOwnerId = (star['commentOwnerId'] ?? '').toString();
            }
            if (videoOwnerId.isEmpty) {
              videoOwnerId = (star['replyOwnerId'] ?? '').toString();
            }
            if (videoOwnerId.isEmpty && _currentUser != null) {
              videoOwnerId = _currentUser!.uid;
            }
            if (videoId.isNotEmpty && videoOwnerId.isNotEmpty) {
              // Route by star type: open replies for reply_star, open comments for comment_star, open stars for video_star
              final String starType = (star['type'] ?? '').toString();
              if (starType == 'reply_star') {
                final String? parentCommentId = star['commentId']?.toString();
                final String? replyId = star['replyId']?.toString();
                if (parentCommentId != null && parentCommentId.isNotEmpty) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VideoQuickViewPage(
                        videoId: videoId,
                        videoOwnerId: videoOwnerId,
                        openReplies: true,
                        parentCommentIdForReplies: parentCommentId,
                        highlightReplyId: replyId,
                      ),
                    ),
                  );
                } else {
                  // Fallback: se non abbiamo il commentId, apri i commenti
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VideoQuickViewPage(
                        videoId: videoId,
                        videoOwnerId: videoOwnerId,
                        openComments: true,
                      ),
                    ),
                  );
                }
                             } else if (starType == 'comment_star') {
                 final String? commentId = star['commentId']?.toString();
                 Navigator.of(context).push(
                   MaterialPageRoute(
                     builder: (_) => VideoQuickViewPage(
                       videoId: videoId,
                       videoOwnerId: videoOwnerId,
                       openComments: true,
                       highlightCommentId: commentId,
                     ),
                   ),
                 );
               } else if (starType == 'video_star') {
                 Navigator.of(context).push(
                   MaterialPageRoute(
                     builder: (_) => VideoQuickViewPage(
                       videoId: videoId,
                       videoOwnerId: videoOwnerId,
                       openStars: true,
                       highlightStarUserId: star['starUserId']?.toString(),
                     ),
                   ),
                 );
               } else { // fallback generico
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VideoQuickViewPage(
                      videoId: videoId,
                      videoOwnerId: videoOwnerId,
                      openStars: true,
                      highlightStarUserId: star['starUserId']?.toString(),
                    ),
                  ),
                );
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ID video non disponibile')),
              );
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User info row
                Row(
                  children: [
                    // Profile image
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: typeColor.withOpacity(0.2),
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: star['starUserProfileImage']?.isNotEmpty == true
                            ? Image.network(
                                star['starUserProfileImage'],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Icon(
                                  Icons.person,
                                  color: typeColor,
                                  size: 20,
                                ),
                              )
                            : Icon(
                                Icons.person,
                                color: typeColor,
                                size: 20,
                              ),
                      ),
                    ),
                    SizedBox(width: 12),
                    
                    // User name and time
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            star['starUserDisplayName'],
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.brightness == Brightness.dark 
                                  ? Colors.white 
                                  : Colors.black87,
                            ),
                          ),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Star icon
                    ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return LinearGradient(
                          colors: [
                            Color(0xFF667eea),
                            Color(0xFF764ba2),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds);
                      },
                      child: Icon(
                        Icons.star,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    
                    // Unread indicator
                    if (!isRead)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: typeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                
                SizedBox(height: 6),
                
                // Content info
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Starred your $contentType',
                    style: TextStyle(
                      fontSize: 12,
                      color: typeColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                
                SizedBox(height: 6),
                
                // Content title
                Text(
                  contentTitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.brightness == Brightness.dark 
                        ? Colors.white70 
                        : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCommentsSheet() {
    setState(() {
      _isCommentsSheetOpen = true;
      _showDeleteAllAction = false;
    });
    
    // Inizializza le animazioni per tutti i commenti quando si apre la tendina
    // Le animazioni verranno inizializzate dinamicamente quando si costruiscono le card
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : Colors.white,
      barrierColor: Colors.black.withOpacity(0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Color(0xFF1E1E1E) 
                  : Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Container(
              height: 60,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Stack(
                children: [
                  // Titolo centrato
                  Center(
                    child: Text(
                      'Comments Received (${_commentNotifications.length})',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.white70 
                            : Colors.black54,
                      ),
                    ),
                  ),
                  // Pulsante delete all a destra
                  if (_commentNotifications.isNotEmpty)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
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
                                  key: ValueKey('delete_all_text'),
                                  onPressed: () async {
                                    await _clearAllCommentNotifications();
                                    setModalState(() {});
                                  },
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size(32, 32),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Delete',
                                    style: TextStyle(
                                      color: Colors.red[600],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  key: ValueKey('delete_all_icon'),
                                  onPressed: () {
                                    setState(() => _showDeleteAllAction = true);
                                    setModalState(() {});
                                  },
                                  icon: Icon(
                                    Icons.clear_all,
                                    size: 20,
                                    color: Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.white70 
                                        : Colors.black54,
                                  ),
                                  tooltip: 'Clear all comments',
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Comments list with StreamBuilder for real-time updates
            Expanded(
              child: StreamBuilder<DatabaseEvent>(
                stream: _database
                    .child('users')
                    .child('users')
                    .child(_currentUser!.uid)
                    .child('notificationcomment')
                    .onValue,
                builder: (context, snapshot) {
                  if (_isCommentsLoading) {
                    return Center(
                      child: Lottie.asset(
                        'assets/animations/MainScene.json',
                        width: 160,
                        height: 160,
                        fit: BoxFit.contain,
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error loading comments',
                        style: TextStyle(color: Colors.red),
                      ),
                    );
                  }
                  
                  if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.comment_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No comments yet',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Comments on your videos will appear here',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  final commentsData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>?;
                  if (commentsData == null || commentsData.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.comment_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No comments yet',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Comments on your videos will appear here',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
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
                  
                  // Ordina per timestamp (più recenti prima)
                  comments.sort((a, b) {
                    final at = a['timestamp'] ?? 0;
                    final bt = b['timestamp'] ?? 0;
                    return bt.compareTo(at);
                  });
                  
                  return ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                    itemCount: comments.length,
                      itemBuilder: (context, index) {
                      final comment = comments[index];
                        return _buildCommentCardWithAnimation(comment);
                    },
                  );
                      },
                    ),
            ),
          ],
        ),
      );
        }),
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _isCommentsSheetOpen = false;
          _showDeleteAllAction = false;
        });
        
        // Pulisci le animazioni quando si chiude la tendina
        _deletingCommentIds.clear();
        _isDeletingComments = false;
        _showDeleteAllStarsAction = false;
      }
    });
  }

  Widget _buildCommentCardWithAnimation(Map<String, dynamic> comment) {
    // Inizializza l'animazione di scorrimento per questo commento
    _initializeCommentSlideAnimation(comment['id']);
    
    final isDeleting = _deletingCommentIds.contains(comment['id']);
    
    // Verifica se l'animazione di scorrimento esiste prima di usarla
    if (!_commentSlideAnimations.containsKey(comment['id'])) {
      return _buildCommentCard(comment);
    }
    
    return SlideTransition(
      position: _commentSlideAnimations[comment['id']]!,
      child: AnimatedOpacity(
        duration: Duration(milliseconds: 300),
        opacity: isDeleting ? 0.0 : 1.0,
        child: _buildCommentCard(comment),
      ),
    );
  }

  Widget _buildStarCardWithAnimation(Map<String, dynamic> star) {
    // Inizializza l'animazione di scorrimento per questa star
    _initializeStarSlideAnimation(star['id']);
    
    final isDeleting = _deletingStarIds.contains(star['id']);
    
    return SlideTransition(
      position: _starSlideAnimations[star['id']]!,
      child: AnimatedOpacity(
        duration: Duration(milliseconds: 300),
        opacity: isDeleting ? 0.0 : 1.0,
        child: _buildStarCard(star),
      ),
    );
  }

  Widget _buildCommentCard(Map<String, dynamic> comment) {
    final theme = Theme.of(context);
    final isRead = comment['read'] as bool;
    final timestamp = comment['timestamp'] as int;
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
    final commentText = comment['text'] as String;
    final isLongComment = commentText.length > 100;
    
    // Load profile image dynamically for this comment
    final userId = comment['userId']?.toString() ?? '';
    final profileImageUrl = comment['userProfileImage']?.toString() ?? '';
    
    return FutureBuilder<String?>(
      future: userId.isNotEmpty ? _loadUserProfileImage(userId) : Future.value(null),
      builder: (context, snapshot) {
        final currentProfileImageUrl = snapshot.data ?? profileImageUrl;
    
    return Dismissible(
      key: Key(comment['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.red.shade400,
              Colors.red.shade600,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.3),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
          ],
        ),
      ),

      confirmDismiss: (direction) async {
        return true; // Elimina direttamente senza conferma
      },
      onDismissed: (direction) {
        // Elimina il commento con animazione
        _deleteCommentNotification(comment['id']);
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          // Effetto vetro semi-trasparente opaco
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.12)
              : Colors.white.withOpacity(0.22),
          borderRadius: BorderRadius.circular(12),
          // Bordo con effetto vetro più sottile
          border: Border.all(
            color: theme.brightness == Brightness.dark
                ? Colors.white.withOpacity(0.2)
                : Colors.white.withOpacity(0.35),
            width: 1,
          ),
          // Ombra per effetto profondità e vetro
          boxShadow: [
            BoxShadow(
              color: theme.brightness == Brightness.dark
                  ? Colors.black.withOpacity(0.35)
                  : Colors.black.withOpacity(0.12),
              blurRadius: theme.brightness == Brightness.dark ? 22 : 18,
              spreadRadius: theme.brightness == Brightness.dark ? 1 : 0,
              offset: const Offset(0, 8),
            ),
            // Ombra interna per effetto vetro
            BoxShadow(
              color: theme.brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.white.withOpacity(0.5),
              blurRadius: 2,
              spreadRadius: -2,
              offset: const Offset(0, 2),
            ),
          ],
          // Gradiente più sottile per effetto vetro
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: theme.brightness == Brightness.dark
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
        child: InkWell(
          onTap: () {
            if (!isRead) {
              _markCommentAsRead(comment['id']);
            }
            final String videoId = (comment['videoId'] ?? '').toString();
            final String videoOwnerId = (comment['videoOwnerId'] ?? '').toString();
            if (videoId.isNotEmpty && videoOwnerId.isNotEmpty) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VideoQuickViewPage(
                    videoId: videoId,
                    videoOwnerId: videoOwnerId,
                    openComments: true,
                    highlightCommentId: comment['id']?.toString(),
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ID video non disponibile')),
              );
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User info row
                Row(
                  children: [
                    // Profile image
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Color(0xFF6C63FF).withOpacity(0.2),
                          width: 1.5,
                        ),
                      ),
                      child: ClipOval(
                        child: currentProfileImageUrl.isNotEmpty
                            ? Image.network(
                                currentProfileImageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Icon(
                                  Icons.person,
                                  color: Color(0xFF6C63FF),
                                  size: 16,
                                ),
                              )
                            : Icon(
                                Icons.person,
                                color: Color(0xFF6C63FF),
                                size: 16,
                              ),
                      ),
                    ),
                    SizedBox(width: 8),
                    
                    // User name and time
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comment['userDisplayName'],
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: theme.brightness == Brightness.dark 
                                  ? Colors.white 
                                  : Colors.black87,
                            ),
                          ),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Unread indicator
                    if (!isRead)
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Color(0xFF6C63FF),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                
                SizedBox(height: 8),
                
                // Comment text with expandable functionality
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      commentText,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.brightness == Brightness.dark 
                            ? Colors.white70 
                            : Colors.black87,
                        height: 1.3,
                      ),
                      maxLines: isLongComment ? 3 : null,
                      overflow: isLongComment ? TextOverflow.ellipsis : null,
                    ),
                    if (isLongComment)
                      TextButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: Text('Full Comment'),
                                content: SingleChildScrollView(
                                  child: Text(
                                    commentText,
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    child: Text('Close'),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                        child: Text(
                          'Read more',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6C63FF),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
                
                SizedBox(height: 6),
                
                // Video title and stats row
                Row(
                  children: [
                    // Video title
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Color(0xFF6C63FF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'on "${comment['videoTitle']}"',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF6C63FF),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    
                    SizedBox(width: 8),
                    

                    
                    SizedBox(width: 8),
                    
                    // Interactive Reply button
                    GestureDetector(
                      onTap: () => _showReplyDialog(comment),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.reply,
                              size: 18,
                              color: Colors.grey[600],
                            ),
                            if (comment['replies_count'] > 0) ...[
                              SizedBox(width: 3),
                              Text(
                                '${comment['replies_count']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unreadCount = _notifications.where((n) => !n['read']).length;

    return Theme(
      data: Theme.of(context).copyWith(
        brightness: theme.brightness,
        scaffoldBackgroundColor: theme.brightness == Brightness.dark 
            ? const Color(0xFF121212) 
            : Colors.white,
        cardColor: theme.brightness == Brightness.dark 
            ? const Color(0xFF1E1E1E) 
            : Colors.white,
        colorScheme: Theme.of(context).colorScheme.copyWith(
          background: theme.brightness == Brightness.dark 
              ? const Color(0xFF121212) 
              : Colors.white,
          surface: theme.brightness == Brightness.dark 
              ? const Color(0xFF1E1E1E) 
              : Colors.white,
        ),
      ),
      child: Scaffold(
        backgroundColor: theme.brightness == Brightness.dark 
            ? const Color(0xFF121212) 
            : Colors.white,
        body: Stack(
          children: [
            // Main content area - no padding, content can scroll behind floating header
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
                  : Column(
                      children: [
                        // Padding trasparente nella parte alta per dare spazio alla top bar flottante
                        SizedBox(height: 20 + MediaQuery.of(context).size.height * 0.06),
                        _buildPasswordChangeInfoBox(),
                        Expanded(
                          child: (_notifications.isEmpty && _expiringTokens.isEmpty && _commentNotifications.isEmpty && _starNotifications.isEmpty)
                              ? Center(child: _buildEmptyState())
                              : SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      // Stars card
                                      if ((_isStarsLoading || _starNotifications.isNotEmpty) && !_isCommentsSheetOpen && !_isStarsSheetOpen)
                                        _buildStarsCard(),
                                      // Comments card
                                      if ((_isCommentsLoading || _commentNotifications.isNotEmpty) && !_isCommentsSheetOpen && !_isStarsSheetOpen)
                                        _buildCommentsCard(),
                                      // Token expiry warning
                                      _buildTokenExpiryWarning(),
                                      // Notifications count
                                      if (_notifications.isNotEmpty)
                                        Container(
                                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: theme.colorScheme.outline.withOpacity(0.1),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                '${_notifications.length} notification${_notifications.length == 1 ? '' : 's'}',
                                                style: theme.textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: theme.colorScheme.onSurface,
                                                ),
                                              ),
                                              if (unreadCount > 0)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: theme.colorScheme.primary,
                                                    borderRadius: BorderRadius.circular(16),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: theme.colorScheme.primary.withOpacity(0.3),
                                                        blurRadius: 4,
                                                        offset: const Offset(0, 1),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.circle,
                                                        size: 8,
                                                        color: Colors.white,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        '$unreadCount unread',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      // Notifications list
                                      ListView.builder(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        padding: const EdgeInsets.only(bottom: 16),
                                        itemCount: _notifications.where((notification) {
                                          if (_searchQuery.isEmpty) return true;
                                          final query = _searchQuery.toLowerCase();
                                          final title = (notification['title'] as String).toLowerCase();
                                          final message = (notification['message'] as String).toLowerCase();
                                          final type = (notification['type'] as String).toLowerCase();
                                          return title.contains(query) ||
                                              message.contains(query) ||
                                              type.contains(query);
                                        }).length,
                                        itemBuilder: (context, index) {
                                          final filteredNotifications = _notifications.where((notification) {
                                            if (_searchQuery.isEmpty) return true;
                                            final query = _searchQuery.toLowerCase();
                                            final title = (notification['title'] as String).toLowerCase();
                                            final message = (notification['message'] as String).toLowerCase();
                                            final type = (notification['type'] as String).toLowerCase();
                                            return title.contains(query) ||
                                                message.contains(query) ||
                                                type.contains(query);
                                          }).toList();
                                          return _buildNotificationCard(filteredNotifications[index], theme);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
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
          ],
        ),
      ),
    );
  }

  // Ritorna la lista di stars filtrata
  List<Map<String, dynamic>> _getFilteredStars() {
    if (_selectedStarFilter == 'all') return _starNotifications;
    return _starNotifications.where((s) => s['type'] == _selectedStarFilter).toList();
  }
  
  // Helper methods for star filter dropdown
  Widget _getStarFilterIcon(String filterType) {
    switch (filterType) {
      case 'all':
        return Icon(Icons.star, color: Theme.of(context).colorScheme.primary, size: 24);
      case 'video_star':
        return Icon(Icons.video_library, color: Color(0xFF6C63FF), size: 24);
      case 'comment_star':
        return Icon(Icons.comment, color: Colors.green, size: 24);
      case 'reply_star':
        return Icon(Icons.reply, color: Colors.orange, size: 24);
      default:
        return Icon(Icons.star, color: Theme.of(context).colorScheme.primary, size: 24);
    }
  }
  
  String _getStarFilterLabel(String filterType) {
    switch (filterType) {
      case 'all':
        return 'All';
      case 'video_star':
        return 'Videos';
      case 'comment_star':
        return 'Comments';
      case 'reply_star':
        return 'Replies';
      default:
        return 'All';
    }
  }
  
  Widget _buildStarFilterOption(String value, String label, IconData icon, Color color, StateSetter setModalState) {
    final theme = Theme.of(context);
    final isSelected = _selectedStarFilter == value;
    
    // Calcola il numero di notifiche per questo tipo
    int count;
    switch (value) {
      case 'all':
        count = _starNotifications.length;
        break;
      case 'video_star':
        count = _starNotifications.where((s) => s['type'] == 'video_star').length;
        break;
      case 'comment_star':
        count = _starNotifications.where((s) => s['type'] == 'comment_star').length;
        break;
      case 'reply_star':
        count = _starNotifications.where((s) => s['type'] == 'reply_star').length;
        break;
      default:
        count = 0;
    }
    
    return InkWell(
      onTap: () {
        setModalState(() {
          _selectedStarFilter = value;
          _showStarFilterDropdown = false;
          _starFilterAnimationController.reverse();
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
            Icon(icon, color: color, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected 
                          ? theme.colorScheme.primary
                          : theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                  SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

  /// Elimina tutte le notifiche di commenti
  Future<void> _clearAllCommentNotifications() async {
    if (_currentUser == null || _commentNotifications.isEmpty) return;

    print('DEBUG: Starting to clear ${_commentNotifications.length} comment notifications');

    try {
      // Attiva l'animazione di eliminazione sfalzata
      setState(() {
        _isDeletingComments = true;
      });

      // Anima i commenti uno alla volta con effetto sfalzato e animazione di scorrimento
      final comments = List<Map<String, dynamic>>.from(_commentNotifications);
      
      print('DEBUG: Initializing slide animations for ${comments.length} comments');
      
      // Assicurati che tutti i controller delle animazioni siano inizializzati
      for (final comment in comments) {
        _initializeCommentSlideAnimation(comment['id']);
      }

      // Anima i commenti uno alla volta con effetto sfalzato
      for (int i = 0; i < comments.length; i++) {
        final comment = comments[i];
        
        // Aggiungi il commento corrente alla lista di quelli in eliminazione
        setState(() {
          _deletingCommentIds.add(comment['id']);
        });
        
        // Avvia l'animazione di scorrimento per questo commento
        print('DEBUG: Animating comment ${i + 1}/${comments.length}: ${comment['id']}');
        await _commentSlideControllers[comment['id']]!.forward();
        
        // Aspetta un po' prima di animare il prossimo commento (effetto sfalzato)
        if (i < comments.length - 1) {
          await Future.delayed(Duration(milliseconds: 60)); // Ridotto per un effetto più fluido
        }
      }

      // Aspetta che tutte le animazioni finiscano
      await Future.delayed(Duration(milliseconds: 300));

      // Elimina tutte le notifiche di commenti dal database
      final ref = _database.child('users').child('users').child(_currentUser!.uid).child('notificationcomment');
      for (final comment in comments) {
        await ref.child(comment['id']).remove();
      }

      // Aggiorna immediatamente lo stato locale per feedback istantaneo
      print('DEBUG: Updating UI state after animations');
      setState(() {
        _commentNotifications.clear();
        _showDeleteAllAction = false;
        _isDeletingComments = false;
        _deletingCommentIds.clear();
      });

      // I controller delle animazioni sono già gestiti nella classe e vengono puliti nel dispose

      // Feedback di successo rimosso - solo log di debug

    } catch (e) {
      print('Error clearing comment notifications: $e');
      
      // In caso di errore, resetta lo stato dell'animazione e mostra errore
      setState(() {
        _isDeletingComments = false;
        _deletingCommentIds.clear();
      });
      
      // Feedback di errore rimosso - solo log di debug
    }
  }

  /// Elimina tutte le notifiche di star filtrate (solo quelle della sezione selezionata)
  Future<void> _clearFilteredStarNotifications() async {
    if (_currentUser == null || _starNotifications.isEmpty) return;

    // Ottieni le star filtrate in base alla sezione selezionata
    final filteredStars = _getFilteredStars();
    if (filteredStars.isEmpty) return;

    print('DEBUG: Starting to clear ${filteredStars.length} filtered star notifications from section: $_selectedStarFilter');

    try {
      // Attiva l'animazione di eliminazione sfalzata
      setState(() {
        _isDeletingStars = true;
      });

      // Assicurati che tutti i controller delle animazioni siano inizializzati
      print('DEBUG: Initializing slide animations for ${filteredStars.length} stars');
      for (final star in filteredStars) {
        _initializeStarSlideAnimation(star['id']);
      }

      // Anima le star una alla volta con effetto sfalzato
      for (int i = 0; i < filteredStars.length; i++) {
        final star = filteredStars[i];
        
        // Aggiungi la star corrente alla lista di quelle in eliminazione
        setState(() {
          _deletingStarIds.add(star['id']);
        });
        
        // Avvia l'animazione di scorrimento per questa star
        print('DEBUG: Animating star ${i + 1}/${filteredStars.length}: ${star['id']}');
        await _starSlideControllers[star['id']]!.forward();
        
        // Aspetta un po' prima di animare la prossima star (effetto sfalzato)
        if (i < filteredStars.length - 1) {
          await Future.delayed(Duration(milliseconds: 60)); // Ridotto per un effetto più fluido
        }
      }

      // Aspetta che tutte le animazioni finiscano
      await Future.delayed(Duration(milliseconds: 300));

      // Elimina tutte le star filtrate dal database
      final ref = _database.child('users').child('users').child(_currentUser!.uid).child('notificationstars');
      for (final star in filteredStars) {
        await ref.child(star['id']).remove();
      }

      // Aggiorna immediatamente lo stato locale per feedback istantaneo
      print('DEBUG: Updating UI state after animations');
      setState(() {
        // Rimuovi solo le star filtrate dalla lista locale
        _starNotifications.removeWhere((s) => filteredStars.any((fs) => fs['id'] == s['id']));
        _showDeleteAllStarsAction = false;
        _isDeletingStars = false;
        _deletingStarIds.clear();
      });

      // I controller delle animazioni sono già gestiti nella classe e vengono puliti nel dispose

      // Feedback di successo rimosso - solo log di debug

    } catch (e) {
      print('Error clearing filtered star notifications: $e');
      
      // In caso di errore, resetta lo stato dell'animazione e mostra errore
      setState(() {
        _isDeletingStars = false;
        _deletingStarIds.clear();
      });
      
      // Feedback di errore rimosso - solo log di debug
    }
  }
} 