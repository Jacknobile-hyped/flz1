import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:twitter_api_v2/twitter_api_v2.dart' as v2;
import 'package:firebase_auth/firebase_auth.dart';
import '../settings_page.dart';
import '../profile_page.dart';
import './social_account_details_page.dart';
import './twitter_login_page.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:viralyst/services/deep_link_service.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';

// IMPORTANT: Twitter accounts are saved ONLY in users/users/{uid}/social_accounts/twitter/{id}
// No longer using social_accounts_index to avoid duplicates

class TwitterPage extends StatefulWidget {
  const TwitterPage({super.key});

  @override
  State<TwitterPage> createState() => _TwitterPageState();
}

class _TwitterPageState extends State<TwitterPage> with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  bool _isLoading = true;
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _inactiveAccounts = [];
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tweetController = TextEditingController();
  bool _obscurePassword = true;
  int _currentTabIndex = 0;
  bool _showInfo = false;
  User? _currentUser;
  final GlobalKey<AnimatedListState> _activeListKey = GlobalKey<AnimatedListState>();
  late TabController _tabController;
  
  // Animation controller for info section
  late AnimationController _animationController;
  late Animation<double> _animation;

  // Twitter API credentials
  static const String _apiKey = 'sTn3lkEWn47KiQl41zfGhjYb4';
  static const String _apiKeySecret = 'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA';
  static const String _bearerToken = 'AAAAAAAAAAAAAAAAAAAAABSU0QEAAAAAo4YuWM0KL95fvPVsVk0EuIp%2B8tM%3DMh7GqySbNJX4qoTC3lpEycVl3x9cqQaRvbt1mwckSXszlBLmzM';
  static const String _accessTokenSecret = 'NxhkhdQifTYU7J5ek1i962RRqECPCs9CyaNDzr8YjLCMw';

  // Twitter API services
  late final v2.TwitterApi _twitterApi;

  // Twitter OAuth 2.0 credentials
  static const String _clientId = 'OHJsZjNtcEhIRk5PUVljWGhDRV86MTpjaQ'; // Client ID corretto da tinfo.md
  static const String _redirectUri = 'viralyst://twitter-auth'; // Deve essere registrato su Twitter Dev Portal
  static const List<String> _scopes = [
    'tweet.read',
    'tweet.write',
    'users.read',
    'offline.access',
    'media.write',
  ];

  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _twitterUserData;
  bool _isAuthenticating = false;
  
  // Variabili temporanee per il flusso OAuth2
  String? _tempCodeVerifier;
  String? _tempState;
  
  // Listener per deep link Twitter OAuth2
  StreamSubscription<Uri?>? _deepLinkSubscription;

  // PKCE helpers
  String _generateCodeVerifier([int length = 64]) {
    final rand = Random.secure();
    final codeUnits = List.generate(length, (index) {
      final n = rand.nextInt(256);
      return n;
    });
    return base64UrlEncode(Uint8List.fromList(codeUnits)).replaceAll('=', '');
  }

  String _codeChallengeFromVerifier(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  Future<void> _startTwitterOAuth() async {
    setState(() => _isAuthenticating = true);
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _codeChallengeFromVerifier(codeVerifier);
    final state = base64UrlEncode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    
    // Salva temporaneamente per il callback
    _tempCodeVerifier = codeVerifier;
    _tempState = state;
    
    // Correggo: solo il valore di scope va percent-encoded, non la lista
    final encodedRedirectUri = Uri.encodeComponent(_redirectUri);
    final scopeString = _scopes.join(' ');
    final encodedScope = Uri.encodeComponent(scopeString); // encode solo il valore
    final authUrl =
        'https://twitter.com/i/oauth2/authorize?response_type=code&client_id=$_clientId&redirect_uri=$encodedRedirectUri&scope=$encodedScope&state=$state&code_challenge=$codeChallenge&code_challenge_method=S256';
    try {
      print('[TWITTER OAUTH] Apertura URL di autorizzazione: $authUrl');
      if (await canLaunchUrl(Uri.parse(authUrl))) {
        await launchUrl(Uri.parse(authUrl), mode: LaunchMode.externalApplication);
        print('[TWITTER OAUTH] Browser aperto per autorizzazione Twitter');
      } else {
        throw Exception('Impossibile aprire il browser per l\'autorizzazione');
      }
    } catch (e) {
      print('[TWITTER OAUTH] Errore durante l\'apertura del browser: $e');
      setState(() => _isAuthenticating = false);
    }
  }

  /// Gestisce il callback OAuth2 con il code estratto dal deep link
  Future<void> handleTwitterCallback(String code, String? state) async {
    print('[TWITTER PAGE] 🎯 handleTwitterCallback chiamata');
    print('[TWITTER PAGE] 🔍 Code ricevuto: ${code.substring(0, 8)}...');
    print('[TWITTER PAGE] 🔍 State ricevuto: $state');
    print('[TWITTER PAGE] 🔍 State salvato: $_tempState');
    print('[TWITTER PAGE] 🔍 Code verifier salvato: ${_tempCodeVerifier != null ? 'SÌ' : 'NO'}');
    
    // Verifica che lo state corrisponda
    if (state != _tempState) {
      print('[TWITTER PAGE] ❌ State mismatch!');
      print('[TWITTER PAGE] ❌ State ricevuto: $state');
      print('[TWITTER PAGE] ❌ State salvato: $_tempState');
      setState(() => _isAuthenticating = false);
      return;
    }
    
    // Verifica che abbiamo il code_verifier
    if (_tempCodeVerifier == null) {
      print('[TWITTER PAGE] ❌ Code verifier mancante!');
      setState(() => _isAuthenticating = false);
      return;
    }
    
    print('[TWITTER PAGE] ✅ State e code verifier validi, procedo con _exchangeCodeForToken');
    
    // Completa il flusso OAuth2
    await _exchangeCodeForToken(code, _tempCodeVerifier!);
    
    // Pulisci le variabili temporanee
    _tempCodeVerifier = null;
    _tempState = null;
    
    print('[TWITTER PAGE] ✅ Flusso OAuth2 completato, variabili temporanee pulite');
  }

  // Dopo aver ottenuto l'access token tramite OAuth2:
  Future<void> _exchangeCodeForToken(String code, String codeVerifier) async {
    print('[TWITTER OAUTH] Inizio scambio code per token...');
    print('[TWITTER OAUTH] code: $code');
    print('[TWITTER OAUTH] code_verifier: $codeVerifier');
    print('[TWITTER OAUTH] redirect_uri: $_redirectUri');
    print('[TWITTER OAUTH] client_id: $_clientId');
    final url = Uri.parse('https://api.twitter.com/2/oauth2/token');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': _redirectUri,
        'code_verifier': codeVerifier,
        'client_id': _clientId,
      },
    );
    print('[TWITTER OAUTH] Risposta token status: ${response.statusCode}');
    print('[TWITTER OAUTH] Risposta token body: ${response.body}');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final String accessToken = data['access_token'];
      final String? refreshToken = data['refresh_token'];
      print('[TWITTER OAUTH] Access token ricevuto: ${accessToken.substring(0, 8)}...');
      print('[TWITTER OAUTH] Refresh token ricevuto: ${refreshToken != null ? refreshToken.substring(0, 8) : 'null'}...');
      setState(() {
        _accessToken = accessToken;
        _refreshToken = refreshToken;
      });
      _initializeTwitterApi();
      await _fetchTwitterUserData(accessToken);
    } else {
      print('Errore scambio code: \n${response.body}');
      setState(() => _isAuthenticating = false);
    }
  }

  Future<void> _fetchTwitterUserData(String accessToken) async {
    print('[TWITTER OAUTH] Richiesta dati utente con access token...');
    final url = Uri.parse('https://api.twitter.com/2/users/me?user.fields=profile_image_url,verified');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
    );
    print('[TWITTER OAUTH] Risposta user status: ${response.statusCode}');
    print('[TWITTER OAUTH] Risposta user body: ${response.body}');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        _twitterUserData = data;
        _isAuthenticating = false;
      });
      // --- SALVA ACCOUNT TWITTER IN FIREBASE DOPO LOGIN OAUTH2 ---
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && data['data'] != null) {
        final twitterUser = data['data'];
        final now = DateTime.now().millisecondsSinceEpoch;
        
        // Controlla se esiste già un account con lo stesso username e se ha già un access_token (OAuth 1)
        bool shouldShowPopup = true;
        String? existingAccountId;
        try {
          final existingAccountsSnapshot = await _database
              .child('users')
              .child('users')
              .child(user.uid)
              .child('social_accounts')
              .child('twitter')
              .get();
          
          if (existingAccountsSnapshot.exists && existingAccountsSnapshot.value is Map) {
            final existingAccounts = existingAccountsSnapshot.value as Map<dynamic, dynamic>;
            for (final entry in existingAccounts.entries) {
              if (entry.value is Map) {
                final accountData = entry.value as Map<dynamic, dynamic>;
                if (accountData['username'] == twitterUser['username']) {
                  existingAccountId = entry.key;
                  
                  // Controlla se ha già access_token (OAuth 1)
                  final hasAccessToken = accountData.containsKey('access_token') && 
                                       accountData['access_token'] != null && 
                                       accountData['access_token'].toString().isNotEmpty;
                  if (hasAccessToken) {
                    shouldShowPopup = false; // Non mostrare popup se ha già access_token
                  }
                  break;
                }
              }
            }
          }
        } catch (e) {
          print('[TWITTER OAUTH] Error checking existing account: $e');
          // In caso di errore, mostra comunque il popup per sicurezza
          shouldShowPopup = true;
        }
        
        // Prepara i dati dell'account
        final accountData = {
          'username': twitterUser['username'] ?? '',
          'display_name': twitterUser['name'] ?? '',
          'profile_image_url': twitterUser['profile_image_url'] ?? '',
          'description': twitterUser['description'] ?? '',
          'twitter_id': twitterUser['id'] ?? '',
          'verified': twitterUser['verified'] ?? false,
          'created_at': now,
          'last_sync': now,
          'status': 'active',
          'access_type': 'oauth2', // Indica che è OAuth 2 (accesso completo)
          'access_token': _accessToken, // OAuth 2 token salvato in campo separato
          'refresh_token': _refreshToken,
          'scopes': _scopes,
        };
        
        // Salva o aggiorna l'account
        if (existingAccountId != null) {
          // Aggiorna l'account esistente
          await _database
              .child('users')
              .child('users')
              .child(user.uid)
              .child('social_accounts')
              .child('twitter')
              .child(existingAccountId)
              .update(accountData);
          print('[TWITTER OAUTH] Updated existing Twitter account: $existingAccountId');
        } else {
          // Crea nuovo account
          final accountRef = _database
              .child('users')
              .child('users')
              .child(user.uid)
              .child('social_accounts')
              .child('twitter')
              .push();
          print('[TWITTER OAUTH] Salvataggio nuovo account Twitter su: ${accountRef.path}');
          await accountRef.set(accountData);
          print('[TWITTER OAUTH] Nuovo account Twitter salvato correttamente in Firebase!');
        }
        
        // Ricarica la lista degli account per mostrare subito il profilo collegato
        await _loadAccounts();
        print('[TWITTER OAUTH] Lista account aggiornata automaticamente');
        
        // Mostra popup solo se necessario
        if (shouldShowPopup) {
          _showTwitterAccessPrompt();
        }
      }
      // --- FINE SALVATAGGIO ---
    } else {
      print('Errore fetch user: \n${response.body}');
      setState(() => _isAuthenticating = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
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
    // NON chiamare _initializeTwitterApi() qui!
    _loadAccounts();
    
    // Registra il callback per il deep link OAuth2
    print('[TWITTER PAGE] 🔗 Registrazione callback per deep link OAuth2');
    DeepLinkService.twitterCallback = handleTwitterCallback;
    print('[TWITTER PAGE] ✅ Callback registrato: ${DeepLinkService.twitterCallback != null ? 'SÌ' : 'NO'}');

    // Listener per deep link Twitter OAuth2
    _deepLinkSubscription = AppLinks().uriLinkStream.listen((Uri? uri) {
      if (uri != null && uri.scheme == 'viralyst' && uri.host == 'twitter-auth') {
        final code = uri.queryParameters['code'];
        final state = uri.queryParameters['state'];
        print('[TWITTER PAGE] 🔗 Deep link Twitter OAuth2 rilevato');
        print('[TWITTER PAGE] 🔍 Code: ${code != null ? '${code.substring(0, 8)}...' : 'null'}');
        print('[TWITTER PAGE] 🔍 State: $state');
        if (code != null && state != null) {
          print('[TWITTER PAGE] ✅ Chiamando handleTwitterCallback direttamente');
          handleTwitterCallback(code, state);
        }
      }
    });
    
    // Gestisci anche il deep link iniziale (se l'app è stata aperta tramite deep link)
    _handleInitialDeepLink();

    // Mostra popup informativo Twitter in fase di test
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasShownTwitterInfo) {
        _hasShownTwitterInfo = true;
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.info_outline,
                      size: 32,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Twitter Testing Phase',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Twitter integration is currently in testing. For now, publishing to Twitter is NOT available.\n\nThis is only temporary: publishing to Twitter will be available soon.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[800],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
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
    });
  }

  @override
  void dispose() {
    _tweetController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _tabController.dispose();
    _animationController.dispose();
    
    // Rimuovi il callback quando la pagina viene distrutta
    print('[TWITTER PAGE] 🔗 Rimozione callback per deep link OAuth2');
    DeepLinkService.twitterCallback = null;
    print('[TWITTER PAGE] ✅ Callback rimosso');

    _deepLinkSubscription?.cancel();
    
    super.dispose();
  }

  void _initializeTwitterApi() {
    if (_accessToken == null) return; // Non inizializzare se manca il token
    _twitterApi = v2.TwitterApi(
      bearerToken: _bearerToken,
      oauthTokens: v2.OAuthTokens(
        consumerKey: _apiKey,
        consumerSecret: _apiKeySecret,
        accessToken: _accessToken!,
        accessTokenSecret: _accessTokenSecret,
      ),
      retryConfig: v2.RetryConfig(
        maxAttempts: 5,
        onExecute: (event) => print(
          'Retry after  [32m${event.intervalInSeconds} [0m seconds... '
          '[${event.retryCount} times]'
        ),
      ),
      timeout: const Duration(seconds: 30),
    );
  }

  // Helper method to sanitize username for Firebase path
  String _sanitizeUsername(String username) {
    return username.replaceAll(RegExp(r'[@.#$\[\]]'), '').toLowerCase();
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

      print('Loading Twitter accounts for user: ${user.uid}');

      final snapshot = await _database
          .child('users')
          .child('users')
          .child(user.uid)
          .child('social_accounts')
          .child('twitter')
          .get();

      print('Database path: users/users/${user.uid}/social_accounts/twitter');
      print('Snapshot exists: ${snapshot.exists}');

      if (snapshot.exists) {
        print('Snapshot value: ${snapshot.value}');
        final data = snapshot.value as Map<dynamic, dynamic>;
        final allAccounts = data.entries.map((entry) => {
              'id': entry.key,
              'username': entry.value['username'] ?? '',
              'displayName': entry.value['display_name'] ?? '',
              'profileImageUrl': entry.value['profile_image_url'] ?? '',
              'verified': entry.value['verified'] ?? false,
              'createdAt': entry.value['created_at'] ?? 0,
              'lastSync': entry.value['last_sync'] ?? 0,
              'status': entry.value['status'] ?? 'active',
              'accessType': entry.value['access_type'] ?? 'oauth1', // Default a oauth1 se non specificato
              'accessToken': entry.value['access_token'] ?? null, // OAuth 1 token
              'accessTokenV2': entry.value['access_token'] ?? null, // OAuth 2 token
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
      // SnackBar rimossa come richiesto
    }
  }

  Future<void> _connectTwitterAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final username = _usernameController.text.trim();
      final sanitizedUsername = _sanitizeUsername(username);
      final now = DateTime.now().millisecondsSinceEpoch;
      
      print('Connecting Twitter account: $username');
      print('Sanitized username: $sanitizedUsername');

      // Initialize Twitter API with OAuth 2.0
      final twitter = v2.TwitterApi(
        bearerToken: _bearerToken,
        oauthTokens: v2.OAuthTokens(
          consumerKey: _apiKey,
          consumerSecret: _apiKeySecret,
          accessToken: _accessToken!,
          accessTokenSecret: _accessTokenSecret,
        ),
        retryConfig: v2.RetryConfig(
          maxAttempts: 3,
          onExecute: (event) => print('Retrying... ${event.retryCount} times.'),
        ),
      );

      // Get user data from Twitter API
      final response = await twitter.users.lookupByName(
        username: username,
        expansions: [
          v2.UserExpansion.pinnedTweetId,
        ],
        userFields: [
          v2.UserField.description,
          v2.UserField.location,
          v2.UserField.profileImageUrl,
          v2.UserField.publicMetrics,
        ],
      );

      if (response.data == null) {
        throw Exception('Twitter account not found');
      }

      final twitterUser = response.data!;
      
      // Controlla se esiste già un account con lo stesso username
      String? existingAccountId;
      try {
        final existingAccountsSnapshot = await _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('social_accounts')
            .child('twitter')
            .get();
        
        if (existingAccountsSnapshot.exists && existingAccountsSnapshot.value is Map) {
          final existingAccounts = existingAccountsSnapshot.value as Map<dynamic, dynamic>;
          for (final entry in existingAccounts.entries) {
            if (entry.value is Map) {
              final accountData = entry.value as Map<dynamic, dynamic>;
              if (accountData['username'] == twitterUser.username) {
                existingAccountId = entry.key;
                break;
              }
            }
          }
        }
      } catch (e) {
        print('Error checking existing account: $e');
      }
      
      // Prepara i dati dell'account
      final accountData = {
        'username': twitterUser.username,
        'username_key': sanitizedUsername,
        'display_name': twitterUser.name,
        'profile_image_url': twitterUser.profileImageUrl ?? '',
        'description': twitterUser.description ?? '',
        'location': twitterUser.location ?? '',
        'followers_count': twitterUser.publicMetrics?.followersCount ?? 0,
        'following_count': twitterUser.publicMetrics?.followingCount ?? 0,
        'tweet_count': twitterUser.publicMetrics?.tweetCount ?? 0,
        'twitter_id': twitterUser.id,
        'created_at': now,
        'last_sync': now,
        'status': 'active',
        'access_type': 'oauth2', // Indica che è OAuth 2 (accesso completo)
        'access_token': _accessToken, // OAuth 2 token salvato in campo separato
        'bearer_token': _bearerToken,
        'api_key': _apiKey,
        'api_key_secret': _apiKeySecret,
        'access_token_secret': _accessTokenSecret,
      };
      
      // Salva o aggiorna l'account
      if (existingAccountId != null) {
        // Aggiorna l'account esistente
        await _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('social_accounts')
            .child('twitter')
            .child(existingAccountId)
            .update(accountData);
        print('Updated existing Twitter account: $existingAccountId');
      } else {
        // Crea nuovo account
        final accountRef = _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('social_accounts')
            .child('twitter')
            .push();
        print('Saving new Twitter account at path: ${accountRef.path}');
        await accountRef.set(accountData);
      }

      // Update user profile with Twitter data
      await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('profile')
          .update({
        'display_name': twitterUser.name,
        'profile_image_url': twitterUser.profileImageUrl ?? '',
        'last_updated': now,
      });

      // REMOVED: No longer saving to social_accounts_index to avoid duplicates
      // Twitter accounts are saved ONLY in users/users/{uid}/social_accounts/twitter/{id}

      if (mounted) {
        // SnackBar rimossa come richiesto
        Navigator.pop(context);
        _loadAccounts();
      }
    } catch (e) {
      print('Error connecting Twitter account: $e');
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _removeAccount(String accountId, String username) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      print('Removing Twitter account: $accountId with username: $username');
      
      // Get the account data to get the username_key
      final accountSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .get();

      if (!accountSnapshot.exists) {
        throw Exception('Account not found');
      }

      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final usernameKey = accountData['username_key'] as String?;

      if (usernameKey == null) {
        print('Warning: username_key not found in account data');
      }

      // Mark the account as inactive
      await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .update({'status': 'inactive'});

      // REMOVED: No longer managing social_accounts_index to avoid duplicates
      // Twitter accounts are managed ONLY in users/users/{uid}/social_accounts/twitter/{id}

      print('Account successfully disconnected');
      _loadAccounts();
      
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } catch (e) {
      print('Error removing account: $e');
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    }
  }

  Future<void> _createTweet(String accountId) async {
    if (_tweetController.text.isEmpty) {
      // SnackBar rimossa come richiesto
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create tweet using Twitter API
      final response = await _twitterApi.tweets.createTweet(
        text: _tweetController.text,
      );

      if (response.data != null) {
        // SnackBar rimossa come richiesto
        _tweetController.clear();
        Navigator.pop(context);
      } else {
        throw Exception('Failed to post tweet');
      }
    } catch (e) {
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _reactivateAccount(String accountId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Get the account data to get the username_key
      final accountSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .get();

      if (!accountSnapshot.exists) {
        throw Exception('Account not found');
      }

      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final usernameKey = accountData['username_key'] as String?;

      if (usernameKey == null) {
        print('Warning: username_key not found in account data');
      }

      // Mark the account as active
      await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .update({'status': 'active'});

      // REMOVED: No longer managing social_accounts_index to avoid duplicates
      // Twitter accounts are managed ONLY in users/users/{uid}/social_accounts/twitter/{id}

      print('Account successfully reactivated');
      _loadAccounts();
      
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } catch (e) {
      print('Error reactivating account: $e');
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
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
              'Are you sure you want to completely remove the Twitter account "@${account['username']}" from your Fluzar account?',
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
                      'This will only remove the account from Fluzar. Your Twitter account will not be affected.',
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

      // Get the account data to get the username_key
      final accountSnapshot = await _database
          .child('users')
          .child('users')
          .child(user.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .get();

      // REMOVED: No longer managing social_accounts_index to avoid duplicates
      // Twitter accounts are managed ONLY in users/users/{uid}/social_accounts/twitter/{id}

      // Remove the account from the database
      await _database
          .child('users')
          .child('users')
          .child(user.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .remove();

      // Refresh the UI
      await _loadAccounts();

      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } catch (e) {
      print('Error removing account: $e');
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showConnectDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1DA1F2).withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  'assets/loghi/logo_twitter.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Select the access method',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.edit_outlined, color: Color(0xFF1DA1F2)),
                      label: const Text('Limited Access'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[850] : Colors.grey[100],
                        foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _navigateToTwitterLoginPage();
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0, bottom: 2),
                        child: Text(
                          'Who should use it?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• Only for publishing/scheduling posts.',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]),),
                            Text('• Analytics are NOT available.',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]),),
                            Text('• Perfect for users who want basic posting functionality.',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]),),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.analytics_outlined, color: Color(0xFF1DA1F2)),
                      label: const Text('Full Access'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[850] : Colors.grey[100],
                        foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _startTwitterOAuth();
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0, bottom: 2),
                        child: Text(
                          'Who should use it?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• Allows publishing/scheduling AND viewing analytics.',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]),),
                            Text('• Choose this if you want complete Twitter integration.',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]),),
                            Text('• Required for those who want statistics and insights.',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]),),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToTwitterLoginPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TwitterLoginPage(),
      ),
    ).then((result) async {
      if (result == true) {
        // Account connected successfully, reload the list
        await _loadAccounts();
        
        // Controlla se l'account appena connesso ha solo OAuth 1 (basic access) 
        // e mostra il popup per invitare a fare l'accesso full
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            final snapshot = await _database
                .child('users')
                .child('users')
                .child(user.uid)
                .child('social_accounts')
                .child('twitter')
                .get();
            
            if (snapshot.exists && snapshot.value is Map) {
              final accounts = snapshot.value as Map<dynamic, dynamic>;
              for (final entry in accounts.entries) {
                if (entry.value is Map) {
                  final accountData = entry.value as Map<dynamic, dynamic>;
                  final hasAccessToken = accountData.containsKey('access_token') && 
                                       accountData['access_token'] != null && 
                                       accountData['access_token'].toString().isNotEmpty;
                                    final hasAccessTokenV2 = accountData.containsKey('access_token') &&
                                         accountData['access_token'] != null &&
                                         accountData['access_token'].toString().isNotEmpty;
                  
                  // Se ha OAuth 1 ma non OAuth 2, mostra il popup per l'accesso full
                  if (hasAccessToken && !hasAccessTokenV2) {
                    // Aggiungi un piccolo delay per assicurarsi che l'UI sia aggiornata
                    Future.delayed(Duration(milliseconds: 500), () {
                      if (mounted) {
                        _showTwitterFullAccessPrompt();
                      }
                    });
                    break;
                  }
                }
              }
            }
          } catch (e) {
            print('Error checking account access after basic login: $e');
          }
        }
      }
    });
  }

  void _showTwitterAccessPrompt() {
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
                        color: Color(0xFF1DA1F2).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.info_outline,
                        size: 24,
                        color: Color(0xFF1DA1F2),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 16),
                
                // Title
                Text(
                  'Twitter Access Required',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                
                SizedBox(height: 8),
                
                // Subtitle
                Text(
                  'To publish content on your Twitter account, you need to complete basic access.',
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
                    color: Color(0xFF1DA1F2).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color(0xFF1DA1F2).withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: Color(0xFF1DA1F2),
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This operation takes only a few seconds',
                          style: TextStyle(
                            color: Color(0xFF1DA1F2),
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 24),
                
                // Action buttons
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _navigateToTwitterLoginPage();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Proceed Now',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTwitterFullAccessPrompt() {
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
                        color: Color(0xFF1DA1F2).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.analytics_outlined,
                        size: 24,
                        color: Color(0xFF1DA1F2),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 16),
                
                // Title
                Text(
                  'Twitter Analytics Access',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                
                SizedBox(height: 8),
                
                // Subtitle
                Text(
                  'To view analytics and insights for your Twitter account, you need to complete full access.',
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
                    color: Color(0xFF1DA1F2).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color(0xFF1DA1F2).withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: Color(0xFF1DA1F2),
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This operation takes only a few seconds',
                          style: TextStyle(
                            color: Color(0xFF1DA1F2),
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 24),
                
                // Action buttons
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _startTwitterOAuth();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF1DA1F2),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Proceed Now',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateTweetDialog(String accountId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.edit, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('Create Tweet'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _tweetController,
              maxLength: 280,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'What\'s happening?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : () => _createTweet(accountId),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Tweet'),
          ),
        ],
      ),
    );
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
                    'assets/loghi/logo_twitter.png',
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Twitter Accounts',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(
                  _showInfo ? Icons.expand_less : Icons.expand_more,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () {
                  setState(() {
                    _showInfo = !_showInfo;
                  });
                },
              ),
            ],
          ),
          if (_showInfo) ...[
            const SizedBox(height: 16),
            _buildInfoItem(
              'Channel Management',
              'Manage your Twitter accounts and track their performance.',
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
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
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
                    fontWeight: FontWeight.bold,
                    color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
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
                                  : Color(0xFF1DA1F2).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Image.asset(
                              'assets/loghi/logo_twitter.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                            ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Twitter Accounts',
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
                          color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
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
                            'Manage your Twitter accounts and track their performance.',
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
                      color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                      boxShadow: [
                        BoxShadow(
                          color: theme.brightness == Brightness.dark 
                              ? Colors.white.withOpacity(0.3)
                              : Colors.black.withOpacity(0.3),
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
                                            : Color(0xFF1DA1F2).withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Image.asset(
                                          'assets/loghi/logo_twitter.png',
                                          width: 64,
                                          height: 64,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Text(
                                        'No Active Twitter Accounts',
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
                                        'Connect your Twitter account to get started',
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
                                            : Color(0xFF1DA1F2).withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Image.asset(
                                          'assets/loghi/logo_twitter.png',
                                          width: 64,
                                          height: 64,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Text(
                                        'No Inactive Twitter Accounts',
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
            onPressed: _showConnectDialog,
            heroTag: 'twitter_logo',
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Connect Twitter Account'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            extendedPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            foregroundColor: Colors.white,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            extendedTextStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
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
                  'description': '',
                  'followersCount': 0,
                },
                platform: 'twitter',
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
                                color: theme.brightness == Brightness.dark 
                                    ? Colors.white.withOpacity(0.2)
                                    : Color(0xFF1DA1F2).withOpacity(0.2),
                          width: 2,
                        ),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.brightness == Brightness.dark 
                                      ? Colors.white.withOpacity(0.1)
                                      : Color(0xFF1DA1F2).withOpacity(0.1),
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
                              color: theme.brightness == Brightness.dark 
                                  ? Colors.white.withOpacity(0.1)
                                  : Color(0xFF1DA1F2).withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                                color: theme.brightness == Brightness.dark 
                                    ? Colors.white.withOpacity(0.2)
                                    : Color(0xFF1DA1F2).withOpacity(0.2),
                          width: 2,
                        ),
                      ),
                            child: Icon(
                        Icons.person,
                        size: 32,
                              color: theme.brightness == Brightness.dark ? Colors.white : Color(0xFF1DA1F2),
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
                                  color: theme.brightness == Brightness.dark 
                                      ? Colors.black.withOpacity(0.3)
                                      : Colors.black.withOpacity(0.1),
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                account['displayName'],
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                            if (account['verified'] == true)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Image.asset(
                                  'assets/verified.png',
                                  width: 16,
                                  height: 16,
                                  fit: BoxFit.contain,
                                ),
                              ),
                          ],
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
                          '${account['username']}',
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
                            color: theme.brightness == Brightness.dark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
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
                        color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                        size: 22,
                      ),
                      tooltip: 'Deactivate Account',
                      onPressed: () => _removeAccount(account['id'], account['username']),
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
                Divider(height: 1, color: theme.brightness == Brightness.dark 
                    ? Colors.grey[700]!.withOpacity(0.3)
                    : Colors.grey.withOpacity(0.15)),
                const SizedBox(height: 12),
                
                // Bottom actions row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isActive ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
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
                    
                    // Badge informativo per account attivi senza access_token (OAuth 1)
                    if (isActive && !(account.containsKey('accessToken') && account['accessToken'] != null && account['accessToken'].toString().isNotEmpty))
                      GestureDetector(
                        onTap: () => _showTwitterAccessPrompt(),
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
                                Icons.info_outline,
                                size: 12,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'NEEDS ACCESS',
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
                      
                    // Badge informativo per account attivi senza access_token (OAuth 2)
                    if (isActive && !(account.containsKey('accessTokenV2') && account['accessTokenV2'] != null && account['accessTokenV2'].toString().isNotEmpty))
                      GestureDetector(
                        onTap: () => _showTwitterFullAccessPrompt(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Color(0xFF1DA1F2).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Color(0xFF1DA1F2).withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 12,
                                color: Color(0xFF1DA1F2),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'ANALYTICS',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1DA1F2),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                            theme.brightness == Brightness.dark ? Colors.grey[400]! : Color(0xFF333333),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds);
                      },
                      child: const Text(
                        'Twitter',
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
                      ? Colors.white.withOpacity(0.1)
                      : Colors.black.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: theme.brightness == Brightness.dark 
                        ? Colors.white.withOpacity(0.2)
                        : Colors.black.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 14,
                      color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Accounts',
                      style: TextStyle(
                        color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
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

  /// Gestisce il deep link iniziale (se l'app è stata aperta tramite deep link)
  Future<void> _handleInitialDeepLink() async {
    try {
      // AppLinks non ha getInitialLink, usiamo un approccio diverso
      // Il deep link iniziale verrà gestito dal listener globale
      print('[TWITTER PAGE] 🔗 Controllo deep link iniziale completato');
    } catch (e) {
      print('[TWITTER PAGE] ❌ Errore nel gestire deep link iniziale: $e');
    }
  }

  bool _hasShownTwitterInfo = false;
} 