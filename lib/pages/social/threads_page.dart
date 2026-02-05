import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'dart:math';
import '../settings_page.dart';
import '../profile_page.dart';
import './social_account_details_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThreadsPage extends StatefulWidget {
  final bool autoConnect;
  
  const ThreadsPage({super.key, this.autoConnect = false});

  @override
  State<ThreadsPage> createState() => _ThreadsPageState();
}

class _ThreadsPageState extends State<ThreadsPage> with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  bool _isLoading = true;
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _inactiveAccounts = [];
  int _currentTabIndex = 0;
  bool _showInfo = false;
  StreamSubscription? _linkSubscription;
  User? _currentUser;
  final GlobalKey<AnimatedListState> _activeListKey = GlobalKey<AnimatedListState>();
  late TabController _tabController;
  
  // Animation controller for info section
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  // Threads OAuth credentials
  static const String clientId = '1406361497206606'; // Threads App ID specifico
  static const String clientSecret = 'dff9514d5f64afc6dedd01af6583faf2'; // Threads App Secret specifico
  static const String redirectUri = 'https://viralyst-redirecturi-threads-users000.netlify.app/';
  static const String customSchemeRedirectUri = 'viralyst://auth/threads-callback';
  static const String authUrl = 'https://threads.net/oauth/authorize';
  static const String tokenUrl = 'https://graph.threads.net/oauth/access_token';
  static const String scopes = 'threads_basic,threads_content_publish';
  
  // Generatore numeri random
  final Random _random = Random();
  
  late SharedPreferences _prefs;
  
  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
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
    
    _loadAccounts();
    _initDeepLinkHandling();
    
    // Timer per il refresh dei token ogni 30 giorni (metà della durata di un token a lunga scadenza)
    Timer.periodic(const Duration(days: 30), (timer) {
      _refreshAllTokens();
    });

    _initPrefs();
    
    // Avvia automaticamente il processo di connessione se richiesto
    if (widget.autoConnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _connectThreadsAccount();
      });
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _tabController.dispose();
    _animationController.dispose(); // Dispose animation controller
    super.dispose();
  }

  Future<void> _initPrefs() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      // Creiamo un'istanza fittizia per evitare null exception
      _prefs = await SharedPreferences.getInstance();
    }
  }

  // Metodo helper per gestire i casi in cui _prefs potrebbe non essere ancora inizializzato
  void _safeSetString(String key, String value) {
    try {
      if (_prefs != null) {
        _prefs.setString(key, value);
      }
    } catch (e) {
    }
  }
  
  void _safeSetInt(String key, int value) {
    try {
      if (_prefs != null) {
        _prefs.setInt(key, value);
      }
    } catch (e) {
    }
  }

  Future<void> _initDeepLinkHandling() async {
    final appLinks = AppLinks();
    
    // Handle initial link
    final initialLink = await appLinks.getInitialAppLink();
    if (initialLink != null) {
      _handleIncomingLink(initialLink.toString());
    }

    // Handle incoming links
    _linkSubscription = appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        _handleIncomingLink(uri.toString());
      }
    }, onError: (err) {
    });
  }

  void _handleIncomingLink(String link) {
    try {
      final uri = Uri.parse(link);
      
      // Gestisci i callback da qualsiasi source che contiene il codice di autorizzazione
      final code = uri.queryParameters['code'];
      if (code != null) {
        
        // Verifica se il link è vecchio (se è stato gestito in precedenza)
        final now = DateTime.now().millisecondsSinceEpoch;
        int lastHandledLinkTime = 0;
        String lastHandledLink = '';
        
        try {
          lastHandledLinkTime = _prefs?.getInt('last_handled_link_time') ?? 0;
          lastHandledLink = _prefs?.getString('last_handled_link') ?? '';
        } catch (e) {
        }
        
        // Se il link è lo stesso di quello gestito negli ultimi 30 secondi, ignoralo
        if (lastHandledLink == link && now - lastHandledLinkTime < 30000) {
          return;
        }
        
        // Salva il timestamp e il link corrente per evitare duplicazioni
        _safeSetInt('last_handled_link_time', now);
        _safeSetString('last_handled_link', link);
        
        _handleAuthCallback(code);
      } else {
        if (mounted) {
          // SnackBar rimossa come richiesto
        }
      }
    } catch (e) {
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    }
  }

  Future<void> _loadAccounts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      setState(() {
        _currentUser = user;
      });
      
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final snapshot = await _database
          .child('users')
          .child('users')
          .child(user.uid)
          .child('social_accounts')
          .child('threads')
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final allAccounts = data.entries.map((entry) => {
          'id': entry.key,
          'username': entry.value['username'] ?? '',
          'displayName': entry.value['display_name'] ?? '',
          'profileImageUrl': entry.value['profile_image_url'] ?? '',
          'createdAt': entry.value['created_at'] ?? 0,
          'lastSync': entry.value['last_sync'] ?? 0,
          'status': entry.value['status'] ?? 'active',
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
      setState(() => _isLoading = false);
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    }
  }

  Future<void> _connectThreadsAccount() async {
    try {
      setState(() => _isLoading = true);
      
      // Generiamo un timestamp e un valore casuale per lo state e la sicurezza
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomValue = _random.nextInt(1000000).toString();
      final dynamicState = 'state_${timestamp}_$randomValue';
      
      // Assicuriamoci che il redirectUri corrisponda esattamente a quello registrato su Threads
      print('Using redirect URI for Threads: $redirectUri');
      
      // Costruisci l'URL di autorizzazione di Threads
      final authUri = Uri.parse('$authUrl?'
          'client_id=$clientId&'
          'redirect_uri=${Uri.encodeComponent(redirectUri)}&'
          'scope=$scopes&'
          'response_type=code&'
          'state=$dynamicState');
      
      print('Launching Threads auth URL: $authUri');
      
      if (await canLaunchUrl(authUri)) {
        print('Launching URL...');
        // Utilizziamo il browser esterno per l'autenticazione Threads
        await launchUrl(
          authUri, 
          mode: LaunchMode.externalApplication,
        );
        print('URL launched successfully');
        // SnackBar rimossa come richiesto
      } else {
        print('Could not launch URL: $authUri');
        throw 'Could not launch $authUri';
      }
    } catch (e) {
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } finally {
        setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAuthCallback(String code) async {
    try {
      // Utilizziamo lo stesso redirectUri usato nella richiesta iniziale
      // print('Using redirect URI for token exchange: $redirectUri');
      
      // Scambia il codice con un token di accesso
      final tokenBody = {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      };
      
      // print('Sending token request to: $tokenUrl');
      // print('Request body: $tokenBody');
      
      final response = await http.post(
        Uri.parse(tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: tokenBody,
      );

      // print('Token response status: [36m");
      // print('Token response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Verifichiamo che la risposta contenga i token necessari
        if (!data.containsKey('access_token') || !data.containsKey('user_id')) {
          throw 'Incomplete token response from Threads: missing required fields';
        }
        
        final shortLivedAccessToken = data['access_token'];
        final userId = data['user_id'];

        // print('Successfully obtained Threads tokens. User ID: $userId');
        
        // Scambia il token a breve scadenza con uno a lunga scadenza (60 giorni)
        final longLivedToken = await _exchangeForLongLivedToken(shortLivedAccessToken) ?? shortLivedAccessToken;

        // Proviamo a ottenere più campi possibili dall'utente
        // Ci sono vari tentativi perché la documentazione non è chiara sui campi disponibili
        final userInfoUrl = 'https://graph.threads.net/$userId?fields=username,id';
        // print('Requesting user info from: $userInfoUrl');
        
        final userInfoResponse = await http.get(
          Uri.parse(userInfoUrl),
          headers: {
            'Authorization': 'Bearer $longLivedToken',
          },
        );

        // print('User info response status: ${userInfoResponse.statusCode}');
        // print('User info response body: ${userInfoResponse.body}');
        
        String profileImageUrl = '';
        // Poiché l'API di Threads potrebbe non fornire l'immagine del profilo direttamente,
        // potremmo tentare di ottenere informazioni aggiuntive dal profilo tramite endpoint alternativi
        
        try {
          // Prova a ottenere avatar tramite /media endpoint se disponibile
          final mediaInfoUrl = 'https://graph.threads.net/$userId/media?fields=caption,id,media_type,media_url,thumbnail_url';
          // print('Trying to get media info from: $mediaInfoUrl');
          
          final mediaResponse = await http.get(
            Uri.parse(mediaInfoUrl),
            headers: {
              'Authorization': 'Bearer $longLivedToken',
            },
          );
          
          // print('Media info response status: ${mediaResponse.statusCode}');
          // if (mediaResponse.statusCode == 200) {
          //   print('Media info response body: ${mediaResponse.body}');
          // }
        } catch (e) {
          // print('Error getting media info: $e');
        }

        if (userInfoResponse.statusCode == 200) {
          final userData = json.decode(userInfoResponse.body);
          String username = userData['username'] ?? 'threads_user';
          
          // Implementazione avanzata avatar per Threads accounts
          // Utilizzo un approccio ibrido con fallback a default_avatar.png
          // Oppure creiamo un avatar avanzato personalizzato
          final String firstLetter = username.isNotEmpty ? username[0].toUpperCase() : 'T';
          
          // Creiamo una palette di colori Threads-inspired
          final List<Map<String, String>> avatarStyles = [
            {'bg': '000000', 'fg': 'FFFFFF'},  // Nero (colore principale Threads)
            {'bg': '262626', 'fg': 'FFFFFF'},  // Grigio scuro
            {'bg': '8E8E8E', 'fg': 'FFFFFF'},  // Grigio medio
            {'bg': 'E0F1FF', 'fg': '1E4C6B'},  // Azzurro chiaro
            {'bg': '1E4C6B', 'fg': 'FFFFFF'},  // Blu scuro
          ];
          
          // Selezioniamo uno stile basato sul nome utente
          final int styleIndex = username.hashCode.abs() % avatarStyles.length;
          final Map<String, String> selectedStyle = avatarStyles[styleIndex];
          
          // Generiamo un avatar personalizzato
          profileImageUrl = 'https://ui-avatars.com/api/'
              '?name=$firstLetter'
              '&background=${selectedStyle['bg']}'
              '&color=${selectedStyle['fg']}'
              '&size=256'
              '&bold=true'
              '&format=png'
              '&rounded=true'
              '&length=1';
          
          // Salva l'account in Firebase
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            // print('Saving Threads account to Firebase for user: ${user.uid}');
            
            final dbPath = 'users/users/${user.uid}/social_accounts/threads/$userId';
            // print('Database path: $dbPath');
            
            await _database
                .child('users')
                .child('users')
                .child(user.uid)
                .child('social_accounts')
                .child('threads')
                .child(userId.toString())
                .set({
              'username': username,
              'display_name': username,
              'profile_image_url': profileImageUrl, // Utilizziamo un servizio di avatar
              'created_at': DateTime.now().millisecondsSinceEpoch,
              'last_sync': DateTime.now().millisecondsSinceEpoch,
              'status': 'active',
              'access_token': longLivedToken,
              'user_id': userId,
              'token_type': 'long_lived',
            });

            // print('Threads account saved successfully');
            await _loadAccounts();

            if (mounted) {
              // SnackBar rimossa come richiesto
            }
          }
        } else {
          // print('Failed to get user info: ${userInfoResponse.statusCode}');
          throw 'Failed to get user info from Threads: ${userInfoResponse.body}';
        }
      } else {
        // print('Failed to get access token: ${response.statusCode}');
        throw 'Failed to get access token from Threads: ${response.body}';
      }
    } catch (e) {
      // print('Error in _handleAuthCallback: $e');
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    }
  }

  Future<void> _removeAccount(String accountId) async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _database
          .child('users')
          .child('users')
          .child(user.uid)
          .child('social_accounts')
          .child('threads')
          .child(accountId)
          .update({
        'status': 'inactive',
        'last_sync': DateTime.now().millisecondsSinceEpoch,
      });

      await _loadAccounts();

      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } catch (e) {
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _reactivateAccount(String accountId) async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _database
          .child('users')
          .child('users')
          .child(user.uid)
          .child('social_accounts')
          .child('threads')
          .child(accountId)
          .update({
        'status': 'active',
        'last_sync': DateTime.now().millisecondsSinceEpoch,
      });

      await _loadAccounts();

      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } catch (e) {
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

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
              'Are you sure you want to completely remove the Threads account "${account['username'] ?? 'threads_user'}" from your Fluzar account?',
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
                      'This will only remove the account from Fluzar. Your Threads account will not be affected.',
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

  // Method to permanently remove the account from database
  Future<void> _permanentlyRemoveAccount(String accountId) async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Remove the account from the database
      await _database
          .child('users')
          .child('users')
          .child(user.uid)
          .child('social_accounts')
          .child('threads')
          .child(accountId)
          .remove();

      // Refresh the UI
      await _loadAccounts();

      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } catch (e) {
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Metodo per scambiare un token a breve scadenza con uno a lunga scadenza (60 giorni)
  Future<String?> _exchangeForLongLivedToken(String shortLivedToken) async {
    try {
      print('Exchanging short-lived token for long-lived token');
      
      final url = Uri.parse('https://graph.threads.net/access_token'
          '?grant_type=th_exchange_token'
          '&client_secret=$clientSecret'
          '&access_token=$shortLivedToken');
      
      print('Sending long-lived token request to: $url');
      
      final response = await http.get(url);
      
      print('Long-lived token response status: ${response.statusCode}');
      print('Long-lived token response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data.containsKey('access_token')) {
          print('Successfully obtained long-lived token, valid for ${data['expires_in']} seconds');
          return data['access_token'];
        } else {
          print('Response does not contain access_token');
          return null;
        }
      } else {
        print('Failed to get long-lived token: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error exchanging for long-lived token: $e');
      return null;
    }
  }

  // Metodo per aggiornare un token a lunga scadenza prima che scada
  Future<String?> _refreshLongLivedToken(String longLivedToken) async {
    try {
      print('Refreshing long-lived token');
      
      final url = Uri.parse('https://graph.threads.net/refresh_access_token'
          '?grant_type=th_refresh_token'
          '&access_token=$longLivedToken');
      
      print('Sending refresh token request to: $url');
      
      final response = await http.get(url);
      
      print('Refresh token response status: ${response.statusCode}');
      print('Refresh token response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data.containsKey('access_token')) {
          print('Successfully refreshed token, valid for ${data['expires_in']} seconds');
          return data['access_token'];
        } else {
          print('Response does not contain access_token');
          return null;
        }
      } else {
        print('Failed to refresh token: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error refreshing token: $e');
      return null;
    }
  }
  
  // Metodo per aggiornare automaticamente i token degli account salvati
  Future<void> _refreshAllTokens() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      for (final account in _accounts) {
        try {
          final accountId = account['id'];
          
          // Recupera il token attuale
          final snapshot = await _database
              .child('users')
              .child('users')
              .child(user.uid)
              .child('social_accounts')
              .child('threads')
              .child(accountId)
              .get();
          
          if (snapshot.exists) {
            final data = snapshot.value as Map<dynamic, dynamic>;
            final accessToken = data['access_token'];
            
            // Aggiorna il token
            final newToken = await _refreshLongLivedToken(accessToken);
            
            if (newToken != null) {
              // Salva il nuovo token
              await _database
                  .child('users')
                  .child('users')
                  .child(user.uid)
                  .child('social_accounts')
                  .child('threads')
                  .child(accountId)
                  .update({
                'access_token': newToken,
                'last_sync': DateTime.now().millisecondsSinceEpoch,
              });
              
              print('Token refreshed for account: $accountId');
            }
          }
        } catch (e) {
          print('Error refreshing token for account ${account['id']}: $e');
        }
      }
    } catch (e) {
      print('Error in _refreshAllTokens: $e');
    }
  }

  Widget _buildInfoDropdown() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
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
                  Image.asset(
                    'assets/loghi/threads_logo.png',
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 12),
          Text(
                    'Threads Accounts',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
                ],
              ),
              IconButton(
                icon: AnimatedIcon(
                  icon: AnimatedIcons.menu_close,
                  progress: _animation,
                  color: Colors.black87,
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
                    'Account Management',
                    'Manage your Threads accounts and track their performance.',
                    Icons.account_box,
                  ),
                  _buildInfoItem(
                    'Interactive Details',
                    'Click on any account to view the videos published with Fluzar.',
                    Icons.touch_app,
                  ),
                  _buildInfoItem(
                    'Account Visibility',
                    'Deactivated accounts won\'t appear in video upload selection.',
                    Icons.visibility_off,
                  ),
                ],
              ),
            ),
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
                  ? Colors.black.withOpacity(0.2)
                  : Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: Colors.black,
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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: theme.brightness == Brightness.dark
                      ? [
                          Colors.white.withOpacity(0.15),
                          Colors.white.withOpacity(0.05),
                        ]
                      : [
                          Colors.white.withOpacity(0.25),
                          Colors.white.withOpacity(0.15),
                        ],
                ),
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
                    blurRadius: 25,
                    spreadRadius: 1,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: theme.brightness == Brightness.dark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.white.withOpacity(0.6),
                    blurRadius: 2,
                    spreadRadius: -2,
                    offset: const Offset(0, -2),
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
                                  ? Colors.black.withOpacity(0.2)
                                  : Colors.black.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Image.asset(
                              'assets/loghi/threads_logo.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Threads Accounts',
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
                          color: Colors.black87,
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
                            'Account Management',
                            'Manage your Threads accounts and track their performance.',
                            Icons.account_box,
                          ),
                          _buildInfoItem(
                            'Interactive Details',
                            'Click on any account to view detailed statistics and information.',
                            Icons.touch_app,
                          ),
                          _buildInfoItem(
                            'Account Visibility',
                            'Deactivated accounts won\'t appear in video upload selection.',
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
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: theme.brightness == Brightness.dark
                        ? [
                            Colors.white.withOpacity(0.15),
                            Colors.white.withOpacity(0.05),
                          ]
                        : [
                            Colors.white.withOpacity(0.25),
                            Colors.white.withOpacity(0.15),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(30),
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
                      blurRadius: 25,
                      spreadRadius: 1,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: theme.brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.white.withOpacity(0.6),
                      blurRadius: 2,
                      spreadRadius: -2,
                      offset: const Offset(0, -2),
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
                      color: Colors.black,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
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
                    onTap: (index) {
                      setState(() {
                        _currentTabIndex = index;
                      });
                    },
                    tabs: const [
                      Tab(text: 'Active Accounts'),
                      Tab(text: 'Inactive Accounts'),
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
                                            ? Colors.black.withOpacity(0.2)
                                            : Colors.black.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Image.asset(
                                        'assets/loghi/threads_logo.png',
                                        width: 64,
                                        height: 64,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      'No Active Threads Accounts',
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
                                        'Connect your Threads account or reactivate it',
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
                                            ? Colors.black.withOpacity(0.2)
                                            : Colors.black.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Image.asset(
                                        'assets/loghi/threads_logo.png',
                                        width: 64,
                                        height: 64,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      'No Inactive Threads Accounts',
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
                                        'Deactivated accounts will appear here',
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
      floatingActionButton: Material(
        elevation: 3,
        shadowColor: Colors.black.withOpacity(0.3),
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(30),
          ),
          child: FloatingActionButton.extended(
            onPressed: _connectThreadsAccount,
            heroTag: 'threads_fab',
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Connect Threads Account'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            extendedPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            foregroundColor: Colors.white,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            extendedTextStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountCard(Map<String, dynamic> account, {required bool isActive}) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: theme.brightness == Brightness.dark
                ? [
                    Colors.white.withOpacity(0.15),
                    Colors.white.withOpacity(0.05),
                  ]
                : [
                    Colors.white.withOpacity(0.25),
                    Colors.white.withOpacity(0.15),
                  ],
          ),
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
              blurRadius: 25,
              spreadRadius: 1,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: theme.brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.white.withOpacity(0.6),
              blurRadius: 2,
              spreadRadius: -2,
              offset: const Offset(0, -2),
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
                    'id': account['id'],
                    'username': account['username'],
                    'displayName': account['displayName'],
                    'profileImageUrl': account['profileImageUrl'],
                    'followersCount': 0,
                    'description': 'Threads Account',
                  },
                  platform: 'threads',
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(20),
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
                        if (account['profileImageUrl']?.isNotEmpty ?? false)
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              image: DecorationImage(
                                image: NetworkImage(account['profileImageUrl']),
                                fit: BoxFit.cover,
                              ),
                              border: Border.all(
                                color: Colors.black.withOpacity(0.2),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
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
                              color: Colors.black.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.black.withOpacity(0.2),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.forum_outlined,
                              size: 32,
                              color: Colors.black,
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
                            account['displayName'] ?? account['username'] ?? 'Threads User',
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
                                Icons.alternate_email,
                                size: 14,
                                color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${account['username'] ?? 'threads_user'}',
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
                                'Connected ${_formatDate(account['createdAt'])}',
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
                        color: Colors.black,
                        size: 22,
                      ),
                      tooltip: 'Deactivate Account',
                      onPressed: () => _removeAccount(account['id']),
                    ) :
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                    
                    // Reactivate button for inactive accounts
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

  String _formatDate(int timestamp) {
    if (timestamp == 0) return 'recently';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // era 12, ora 8
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: theme.brightness == Brightness.dark
              ? [
                  Colors.white.withOpacity(0.15),
                  Colors.white.withOpacity(0.05),
                ]
              : [
                  Colors.white.withOpacity(0.25),
                  Colors.white.withOpacity(0.15),
                ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
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
            blurRadius: 25,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: theme.brightness == Brightness.dark
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.6),
            blurRadius: 2,
            spreadRadius: -2,
            offset: const Offset(0, -2),
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
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8), // padding più ampio
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_back_ios,
                      color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Threads',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                        letterSpacing: -0.5,
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
                      ? Colors.black.withOpacity(0.2)
                      : Colors.black.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: theme.brightness == Brightness.dark 
                        ? Colors.black.withOpacity(0.4)
                        : Colors.black.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      size: 14,
                      color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Accounts',
                      style: TextStyle(
                        color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
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
} 