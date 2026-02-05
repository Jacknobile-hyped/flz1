import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert' show json, utf8, jsonDecode, jsonEncode;
import 'dart:io' show Platform;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../settings_page.dart';
import '../profile_page.dart';
import './social_account_details_page.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:intl/intl.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:video_player/video_player.dart';

// Moved outside the _InstagramPageState class
class _AppLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  
  _AppLifecycleObserver({required this.onResume});
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}

class InstagramPage extends StatefulWidget {
  final bool autoConnect;
  final String? autoConnectType;
  
  const InstagramPage({super.key, this.autoConnect = false, this.autoConnectType});

  @override
  State<InstagramPage> createState() => _InstagramPageState();
}

class _InstagramPageState extends State<InstagramPage> with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  bool _isLoading = true;
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _inactiveAccounts = [];
  int _currentTabIndex = 0;
  bool _showInfo = false;
  User? _currentUser;
  final GlobalKey<AnimatedListState> _activeListKey = GlobalKey<AnimatedListState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  StreamSubscription? _linkSubscription;
  late final _AppLifecycleObserver _lifecycleObserver;
  late TabController _tabController;
  
  // Animation controller for info section
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  // Video player controller for tutorial
  VideoPlayerController? _tutorialVideoController;
  bool _isTutorialVideoInitialized = false;
  
  // Second video player controller for the "connect to Facebook page" tutorial
  VideoPlayerController? _pageConnectVideoController;
  bool _isPageConnectVideoInitialized = false;

  // Instagram API configuration - updated with business scope values
  final String _instagramAppId = '2455386634795485';
  final String _instagramAppSecret = 'a37939ad397bd216f1b963f350c192c2';
  // IMPORTANTE: Deve essere ESATTAMENTE lo stesso in ogni richiesta, CON slash finale
  final String _redirectUri = 'https://viralyst-redirecturi.netlify.app/';
  final String _customUriSchemeRedirect = 'viralyst://auth/instagram-callback';
  
  // Nuovi scope per Instagram Business secondo 2VEDI.md
  final String _instagramBusinessScopes = 'instagram_business_basic,'
                                         'instagram_business_content_publish,'
                                         'instagram_business_manage_comments,'
                                         'instagram_business_manage_messages,'
                                         'instagram_business_manage_insights';

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    // Initialize TabController
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
    
    // Inizializzo l'observer con il callback per ricaricare gli account
    _lifecycleObserver = _AppLifecycleObserver(onResume: () {
      if (mounted) {
        _loadAccounts();
      }
    });
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _loadAccounts();
    _initDeepLinkHandling();
    
    // Avvia automaticamente il processo di connessione se richiesto
    if (widget.autoConnectType == 'basic') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _connectInstagramAccount();
      });
    } else if (widget.autoConnectType == 'advanced') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _connectInstagramViaFacebook();
      });
    } else if (widget.autoConnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _connectInstagramViaFacebook();
      });
    }
    
    // Initialize tutorial video controller
    _initializeTutorialVideo();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _linkSubscription?.cancel();
    // Rimuovo l'observer quando la pagina viene smaltita
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _tabController.dispose(); // Dispose TabController
    _animationController.dispose(); // Dispose animation controller
    
    // Dispose tutorial video controller
    _tutorialVideoController?.dispose();
    // Dispose page connect tutorial video controller
    _pageConnectVideoController?.dispose();
    
    super.dispose();
  }

  Future<void> _initDeepLinkHandling() async {
    print('Initializing Instagram deep link handling...');
    final appLinks = AppLinks();
    
    // Handle initial link
    final initialLink = await appLinks.getInitialAppLink();
    print('Initial link: $initialLink');
    
    // Verifica se l'utente è già autenticato prima di elaborare l'initial link
    if (initialLink != null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Verifica se l'utente ha già un account Instagram collegato
        final snapshot = await _database
            .child('users')
            .child(user.uid)
            .child('instagram')
            .get();
        
        // Elabora l'initial link solo se l'utente non ha ancora account Instagram collegati
        if (!snapshot.exists || (snapshot.value as Map<dynamic, dynamic>).isEmpty) {
          _handleIncomingLink(initialLink.toString());
        } else {
          print('Instagram account already connected, ignoring initial link');
        }
      } else {
        _handleIncomingLink(initialLink.toString());
      }
    }

    // Handle incoming links
    _linkSubscription = appLinks.uriLinkStream.listen((Uri? uri) {
      print('Received deep link: $uri');
      if (uri != null) {
        _handleIncomingLink(uri.toString());
      }
    }, onError: (err) {
      print('Error handling incoming links: $err');
    });
  }

  void _handleIncomingLink(String link) {
    print('Handling incoming link for Instagram: $link');
    try {
      final uri = Uri.parse(link);
      print('Parsed URI: $uri');
      
      // Check if this is our Instagram callback URI via the custom scheme
      if (uri.scheme == 'viralyst' && uri.host == 'auth' && uri.path == '/instagram-callback') {
        final code = uri.queryParameters['code'];
        final error = uri.queryParameters['error'];
        final errorDescription = uri.queryParameters['description'];
        
        print('Instagram callback parameters - code: $code, error: $error, description: $errorDescription');
        
        if (code != null) {
          // Success case - we have a code to exchange for a token
          _exchangeCodeForToken(code);
        } else if (error != null) {
          // Error case
          String errorMessage = 'Instagram authentication failed';
          if (errorDescription != null) {
            errorMessage += ': $errorDescription';
          }
          
          print('Instagram auth error: $errorMessage');
                // SnackBar removed as requested
        } else {
          print('No code or error parameter found in callback');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid Instagram callback received')),
            );
          }
        }
      } else if (uri.scheme == 'https' && 
                ((uri.host == 'viralyst-redirecturi.netlify.app') ||
                 (uri.host == 'viralyst.online' && uri.path == '/auth/instagram-callback'))) {
        // This is a direct HTTPS callback, not expected in normal flow
        // But handle it anyway as a fallback
        final code = uri.queryParameters['code'];
        print('HTTPS callback received directly (not expected): $code');
        if (code != null) {
          _exchangeCodeForToken(code);
        } else {
          print('No code parameter found in direct HTTPS callback');
          // SnackBar removed as requested
        }
      } else {
        print('URI does not match any expected callback format: ${uri.toString()}');
      }
    } catch (e) {
      print('Error parsing incoming link: $e');
      // SnackBar removed as requested
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

      print('Loading Instagram accounts for user: ${user.uid}');

      // Corretto percorso del database secondo la struttura in databasefirebase.json
      // Path: users/WZn8hdkvlpSMisViSOsBZQpFUhJ3/instagram
      final snapshot = await _database
          .child('users')
          .child(user.uid)
          .child('instagram')
          .get();

      print('Database path: users/${user.uid}/instagram');
      print('Snapshot exists: ${snapshot.exists}');

      if (snapshot.exists) {
        print('Snapshot value: ${snapshot.value}');
        final data = snapshot.value as Map<dynamic, dynamic>;
        final allAccounts = data.entries.map((entry) => {
              'id': entry.key,
              'username': entry.value['username'] ?? '',
              'displayName': entry.value['display_name'] ?? '',
              'profileImageUrl': entry.value['profile_image_url'] ?? '',
              'createdAt': entry.value['created_at'] ?? 0,
              'lastSync': entry.value['last_sync'] ?? 0,
              'status': entry.value['status'] ?? 'active',
              'access_token': entry.value['access_token'] ?? null,
              'facebook_access_token': entry.value['facebook_access_token'] ?? null, // AGGIUNTO
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
      // SnackBar removed as requested
    }
  }

  // RIMUOVO: _connectInstagramAccount e _startInstagramAuth
  // AGGIUNGO: Nuovo metodo per login tramite Facebook
  Future<void> _connectInstagramViaFacebook() async {
    try {
      setState(() => _isLoading = true);

      // 1. Login Facebook
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: [
          'public_profile',
          'email',
          'pages_show_list',
          'pages_read_engagement',
          'pages_read_user_content',
          'instagram_basic',
          'instagram_manage_insights',
          'instagram_manage_comments',
        ],
      );

      if (result.status != LoginStatus.success) {
        throw Exception('Facebook login failed:  ${result.message}');
      }

      final accessToken = result.accessToken!.token;

      // 2. Recupera le pagine gestite
      final pagesResponse = await http.get(
        Uri.parse('https://graph.facebook.com/v19.0/me/accounts?fields=id,name,instagram_business_account,access_token&access_token=$accessToken'),
      );
      final pagesData = jsonDecode(pagesResponse.body);

      if (pagesData['data'] == null || pagesData['data'].isEmpty) {
        // Mostra popup informativo minimal in inglese
        if (mounted) {
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
                    Icon(Icons.info_outline, color: Color(0xFFC13584), size: 36),
                    const SizedBox(height: 16),
                    Text(
                      'No Instagram account linked',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No Instagram account is linked to any Facebook page of the selected profile.\n\nTo continue, you can:\n• Select a Facebook profile that manages pages linked to Instagram accounts.\n• Link your Instagram business account to a Facebook page.\n• Or simply use the Basic Access method.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFC13584),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        throw Exception('No Facebook pages found or no Instagram business accounts linked.');
      }

      // 3. Cerca la pagina con account Instagram collegato
      Map? instagramAccount;
      String? pageAccessToken;
      for (final page in pagesData['data']) {
        if (page['instagram_business_account'] != null && page['access_token'] != null) {
          instagramAccount = page['instagram_business_account'];
          pageAccessToken = page['access_token'];
          break;
        }
      }

      if (instagramAccount == null || pageAccessToken == null) {
        throw Exception('No Instagram business account linked to your Facebook pages or missing page access token.');
      }

      final instagramId = instagramAccount['id'];

      print('USO PAGE ACCESS TOKEN per chiamata IG business: $pageAccessToken');

      // 4. Recupera i dati dell'account Instagram usando il page access token e graph.facebook.com
      final igDataResponse = await http.get(
        Uri.parse('https://graph.facebook.com/v19.0/$instagramId?fields=id,username,profile_picture_url,followers_count,media_count,name,biography,website&access_token=$pageAccessToken'),
      );
      print('igDataResponse status: ${igDataResponse.statusCode}');
      print('igDataResponse body: ${igDataResponse.body}');
      if (igDataResponse.statusCode != 200) {
        throw Exception('Failed to get Instagram business data: ${igDataResponse.body}');
      }
      final igData = jsonDecode(igDataResponse.body);

      // Gestione display_name e profile_image_url come nel vecchio metodo
      String profileImageUrl = '';
      String displayName = igData['name'] ?? igData['username'] ?? '';
      int followersCount = igData['followers_count'] ?? 0;
      final originalProfileImageUrl = igData['profile_picture_url'] ?? '';
      if (originalProfileImageUrl.isNotEmpty) {
        try {
          final cloudflareProfileImageUrl = await _downloadAndUploadProfileImage(originalProfileImageUrl, instagramId);
          print('cloudflareProfileImageUrl: $cloudflareProfileImageUrl');
          if (cloudflareProfileImageUrl != null) {
            profileImageUrl = cloudflareProfileImageUrl;
      } else {
            profileImageUrl = originalProfileImageUrl;
          }
        } catch (e) {
          print('Errore upload Cloudflare: ${e.toString()}');
          profileImageUrl = originalProfileImageUrl;
        }
      }

      print('Valori PRIMA DEL SALVATAGGIO: displayName=$displayName, profileImageUrl=$profileImageUrl, followersCount=$followersCount');

      // 5. Salva su Firebase come già fai ora
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Controlla se esiste già un account con lo stesso username e determina se mostrare il popup
      bool shouldShowPopup = false; // Default: non mostrare popup
      try {
        final existingAccountsSnapshot = await _database.child('users/${user.uid}/instagram').get();
        if (existingAccountsSnapshot.exists && existingAccountsSnapshot.value is Map) {
          final existingAccounts = existingAccountsSnapshot.value as Map<dynamic, dynamic>;
          
          // Cerca un account con lo stesso username
          for (final entry in existingAccounts.entries) {
            if (entry.value is Map) {
              final accountData = entry.value as Map<dynamic, dynamic>;
              if (accountData['username'] == igData['username']) {
                // Trovato account con stesso username, controlla i token
                final hasAccessToken = accountData.containsKey('access_token') && 
                                     accountData['access_token'] != null && 
                                     accountData['access_token'].toString().isNotEmpty;
                final hasFacebookAccessToken = accountData.containsKey('facebook_access_token') && 
                                             accountData['facebook_access_token'] != null && 
                                             accountData['facebook_access_token'].toString().isNotEmpty;
                
                // Mostra popup solo se ha access_token ma NON ha facebook_access_token
                if (hasAccessToken && !hasFacebookAccessToken) {
                  shouldShowPopup = true;
                }
                break;
              }
            }
          }
        }
      } catch (e) {
        print('Error checking existing tokens: $e');
        // In caso di errore, non mostrare il popup per sicurezza
        shouldShowPopup = false;
      }

      // Controlla se esiste già un account con lo stesso username
      final existingAccountsSnapshot = await _database.child('users/${user.uid}/instagram').get();
      String? existingAccountId;
      if (existingAccountsSnapshot.exists) {
        final existingAccounts = existingAccountsSnapshot.value as Map<dynamic, dynamic>;
        for (final entry in existingAccounts.entries) {
          if (entry.value is Map) {
            final accountData = entry.value as Map<dynamic, dynamic>;
            if (accountData['username'] == igData['username']) {
              existingAccountId = entry.key;
              break;
            }
          }
        }
      }

      try {
        final accountData = {
          'username': igData['username'],
          'display_name': displayName,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'last_sync': DateTime.now().millisecondsSinceEpoch,
          'status': 'active',
          'facebook_access_token': pageAccessToken,
          'user_id': instagramId,
          'profile_image_url': profileImageUrl,
          'followers_count': followersCount,
          'media_count': igData['media_count'] ?? 0,
          'account_type': 'BUSINESS',
          'permissions': '',
          'is_business_account': true,
          'biography': igData['biography'] ?? '',
          'website': igData['website'] ?? '',
          // AGGIUNTO: data di accesso tramite Facebook
          'facebook_connected_at': DateTime.now().millisecondsSinceEpoch,
        };

        if (existingAccountId != null) {
          // Aggiorna l'account esistente
          await _database.child('users/${user.uid}/instagram/$existingAccountId').update(accountData);
          print('Updated existing Instagram account: $existingAccountId');
        } else {
          // Crea nuovo account
          await _database.child('users/${user.uid}/instagram/$instagramId').set(accountData);
          print('Created new Instagram account: $instagramId');
        }

        print('Salvataggio su Firebase riuscito per userId=${user.uid}, instagramId=$instagramId');
      } catch (e) {
        print('ERRORE nel salvataggio su Firebase: ${e.toString()}');
      }

      await _loadAccounts();

      // SnackBar removed as requested

      // Mostra popup solo se necessario
      if (shouldShowPopup) {
        // Controlla se l'account ha già access_token
        final existingAccountsSnapshot2 = await _database.child('users/${user.uid}/instagram').get();
        bool hasAccessToken = false;
        if (existingAccountsSnapshot2.exists && existingAccountsSnapshot2.value is Map) {
          final existingAccounts2 = existingAccountsSnapshot2.value as Map<dynamic, dynamic>;
          for (final entry in existingAccounts2.entries) {
            if (entry.value is Map) {
              final accountData = entry.value as Map<dynamic, dynamic>;
              if (accountData['username'] == igData['username'] && accountData.containsKey('access_token') && accountData['access_token'] != null && accountData['access_token'].toString().isNotEmpty) {
                hasAccessToken = true;
                break;
              }
            }
          }
        }
        if (!hasAccessToken) {
          _showInstagramAccessPrompt();
        }
      }
    } catch (e) {
      print('Error connecting Instagram via Facebook: $e');
      // SnackBar removed as requested
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showWebViewDialog(String authUrl) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            print('WebView navigating to: ${request.url}');
            
            // Check if the URL is our callback URL
            if (request.url.startsWith(_redirectUri) || 
                request.url.startsWith(_customUriSchemeRedirect)) {
              final uri = Uri.parse(request.url);
              final code = uri.queryParameters['code'];
              if (code != null) {
                print('Received auth code from WebView: $code');
                // Close the WebView dialog
                Navigator.of(context).pop();
                // Exchange the code for token
                _exchangeCodeForToken(code);
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(authUrl));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('Instagram Authorization'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  Navigator.of(context).pop();
                  // Clear pending auth state
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null) {
                    _database.child('users/${user.uid}/instagram_pending_auth').remove();
                  }
                },
              ),
            ),
            SizedBox(
              height: 500,
              child: WebViewWidget(controller: controller),
            ),
          ],
        ),
      ),
    );
  }

  // Metodo per scaricare l'immagine profilo da un URL e salvarla su Cloudflare R2
  Future<String?> _downloadAndUploadProfileImage(String imageUrl, String userId) async {
    try {
      print('Downloading profile image from: $imageUrl');
      
      // Download dell'immagine
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        print('Failed to download image: ${response.statusCode}');
        return null;
      }
      
      final imageBytes = response.bodyBytes;
      print('Downloaded image size: ${imageBytes.length} bytes');
      
      // Determina l'estensione del file basandosi sul Content-Type
      String extension = 'jpg'; // Default
      final contentType = response.headers['content-type'];
      if (contentType != null) {
        if (contentType.contains('png')) {
          extension = 'png';
        } else if (contentType.contains('jpeg') || contentType.contains('jpg')) {
          extension = 'jpg';
        } else if (contentType.contains('gif')) {
          extension = 'gif';
        }
      }
      
      // Genera il nome del file per Cloudflare R2
      final fileName = 'profilePictures/${userId}.$extension';
      
      // Upload su Cloudflare R2
      final cloudflareUrl = await _uploadImageToCloudflareR2(imageBytes, fileName, contentType ?? 'image/jpeg');
      
      print('Profile image uploaded to Cloudflare R2: $cloudflareUrl');
      return cloudflareUrl;
      
    } catch (e) {
      print('Error downloading and uploading profile image: $e');
      return null;
    }
  }
  
  // Metodo per uploadare un'immagine su Cloudflare R2
  Future<String> _uploadImageToCloudflareR2(Uint8List imageBytes, String fileName, String contentType) async {
    try {
      print('Uploading image to Cloudflare R2: $fileName');
      print('Content-Type: $contentType');
      print('Image size: ${imageBytes.length} bytes');
      
      // Cloudflare R2 credentials - usando le credenziali corrette da storage.md
      final String accessKeyId = '5e181628bad7dc5481c92c6f3899efd6';
      final String secretKey = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
      final String endpoint = 'https://3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com';
      final String bucketName = 'videos';
      final String accountId = '3d945eb681944ec5965fecf275e41a9b';
      final String region = 'auto'; // R2 usa 'auto' come regione
      
      // Calcola SHA-256 hash del contenuto
      final List<int> contentHash = sha256.convert(imageBytes).bytes;
      final String payloadHash = hex.encode(contentHash);
      
      // Imposta le informazioni della richiesta
      final String httpMethod = 'PUT';
      
      // SigV4 richiede dati in formato ISO8601
      final now = DateTime.now().toUtc();
      final String amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
      final String dateStamp = DateFormat("yyyyMMdd").format(now);
      
      // Host e URI
      final Uri uri = Uri.parse('$endpoint/$bucketName/$fileName');
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
      
      // Ordina gli header lessicograficamente
      final sortedHeaderKeys = headers.keys.toList()..sort();
      for (final key in sortedHeaderKeys) {
        canonicalHeaders += '${key.toLowerCase()}:${headers[key]}\n';
        signedHeaders += '${key.toLowerCase()};';
      }
      signedHeaders = signedHeaders.substring(0, signedHeaders.length - 1); // Rimuovi l'ultimo punto e virgola
      
      // Canonical request
      final String canonicalUri = '/$bucketName/$fileName';
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
      
      // Crea URL della richiesta
      final String uploadUrl = '$endpoint/$bucketName/$fileName';
      
      // Crea richiesta con headers
      final http.Request request = http.Request('PUT', Uri.parse(uploadUrl));
      request.headers['Host'] = host;
      request.headers['Content-Type'] = contentType;
      request.headers['Content-Length'] = imageBytes.length.toString();
      request.headers['X-Amz-Content-Sha256'] = payloadHash;
      request.headers['X-Amz-Date'] = amzDate;
      request.headers['Authorization'] = authorizationHeader;
      
      // Aggiungi body dell'immagine
      request.bodyBytes = imageBytes;
      
      // Invia la richiesta
      final streamedRequest = http.StreamedRequest(
        request.method,
        request.url,
      );
      
      // Aggiungi tutti gli header alla richiesta streamed
      request.headers.forEach((key, value) {
        streamedRequest.headers[key] = value;
      });
      
      // Aggiungi i bytes dell'immagine
      streamedRequest.sink.add(imageBytes);
      streamedRequest.sink.close();
      
      // Invia la richiesta e ottieni la risposta
      final streamedResponse = await streamedRequest.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Genera URL pubblico nel formato corretto
        // Usa il formato pub-[accountId].r2.dev
        final String publicUrl = 'https://pub-$accountId.r2.dev/$fileName';
        
        print('Image uploaded successfully to Cloudflare R2');
        print('Generated public URL: $publicUrl');
        
        // Verifica che l'URL sia accessibile
        try {
          final verifyResponse = await http.head(Uri.parse(publicUrl))
              .timeout(Duration(seconds: 5));
          
          if (verifyResponse.statusCode >= 200 && verifyResponse.statusCode < 300) {
            print('URL verified and accessible: $publicUrl');
          } else {
            print('WARNING: URL might not be accessible: $publicUrl (status: ${verifyResponse.statusCode})');
          }
        } catch (e) {
          print('WARNING: Unable to verify URL accessibility: $e');
        }
        
        return publicUrl;
      } else {
        throw Exception('Error uploading to Cloudflare R2: Code ${response.statusCode}, Response: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error uploading to Cloudflare R2: $e');
    }
  }

  Future<void> _exchangeCodeForToken(String code) async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // IMPORTANTE: Deve essere IDENTICO a quello usato nell'autorizzazione iniziale
      // Usiamo la variabile di classe che include lo slash finale
      final redirectUri = _redirectUri;

      print('Exchanging code for token with parameters:');
      print('client_id: $_instagramAppId');
      print('redirect_uri: $redirectUri');
      print('code: $code');

      // Richiesta POST all'endpoint oauth/access_token
      final tokenResponse = await http.post(
        Uri.parse('https://api.instagram.com/oauth/access_token'),
        body: {
          'client_id': _instagramAppId,
          'client_secret': _instagramAppSecret,
          'grant_type': 'authorization_code',
          'redirect_uri': redirectUri,
          'code': code,
        },
      );

      print('Token response status code: ${tokenResponse.statusCode}');
      print('Token response body: ${tokenResponse.body}');

      if (tokenResponse.statusCode != 200) {
              // Error dialog removed as requested
        throw Exception('Failed to get access token: ${tokenResponse.body}');
      }

      // Elaborazione della risposta secondo il formato atteso dalla Instagram API
      final tokenData = jsonDecode(tokenResponse.body);
      
      // La risposta potrebbe variare in base alla versione dell'API
      // Controlliamo entrambi i formati possibili
      var accessToken = '';
      var instagramUserId = '';
      
      if (tokenData.containsKey('access_token')) {
        // Formato diretto
        accessToken = tokenData['access_token'];
        instagramUserId = tokenData['user_id']?.toString() ?? '';
      } else if (tokenData.containsKey('data')) {
        // Formato con oggetto data
        accessToken = tokenData['data'][0]?['access_token'] ?? '';
        instagramUserId = tokenData['data'][0]?['user_id']?.toString() ?? '';
      }
      
      if (accessToken.isEmpty || instagramUserId.isEmpty) {
        throw Exception('Failed to parse access token or user ID from response');
      }
      
      print('Received access token: $accessToken');
      print('Instagram user ID: $instagramUserId');

      // Per memorizzare le informazioni del token a lunga durata
      Map<String, dynamic> longLivedTokenData = {};

      // Ottieni un token di lunga durata (60 giorni)
      final longLivedTokenResponse = await http.get(
        Uri.parse(
          'https://graph.instagram.com/access_token'
          '?grant_type=ig_exchange_token'
          '&client_secret=$_instagramAppSecret'
          '&access_token=$accessToken'
        ),
      );

      print('Long-lived token response status code: ${longLivedTokenResponse.statusCode}');
      print('Long-lived token response body: ${longLivedTokenResponse.body}');

      if (longLivedTokenResponse.statusCode != 200) {
        print('Failed to get long-lived token: ${longLivedTokenResponse.body}');
        // Continuiamo comunque con il token a breve scadenza
      } else {
        longLivedTokenData = jsonDecode(longLivedTokenResponse.body);
        // Aggiorna l'access token con quello a lunga durata
        accessToken = longLivedTokenData['access_token'];
        print('Received long-lived access token with expiry in ${longLivedTokenData['expires_in']} seconds');
      }

      // Get Instagram user details using the Business API
      final userResponse = await http.get(
        Uri.parse(
          'https://graph.instagram.com/$instagramUserId'
          '?fields=id,username,account_type,media_count'
          '&access_token=$accessToken'
        ),
      );

      print('User details response status code: ${userResponse.statusCode}');
      print('User details response body: ${userResponse.body}');

      if (userResponse.statusCode != 200) {
        // Error dialog removed as requested
        throw Exception('Failed to get Instagram user details: ${userResponse.body}');
      }

      final userData = jsonDecode(userResponse.body);
      
      // Get user profile picture and other business details
      String profileImageUrl = '';
      int followersCount = 0;
      
      try {
        // Tentativo di ottenere l'immagine del profilo e i follower
        final businessInfoResponse = await http.get(
          Uri.parse(
            'https://graph.instagram.com/$instagramUserId'
            '?fields=profile_picture_url,followers_count,biography,name,website'
            '&access_token=$accessToken'
          ),
        );
        
        if (businessInfoResponse.statusCode == 200) {
          final businessInfoData = jsonDecode(businessInfoResponse.body);
          final originalProfileImageUrl = businessInfoData['profile_picture_url'] ?? '';
          followersCount = businessInfoData['followers_count'] ?? 0;
          print('Retrieved business info: $businessInfoData');
          
          // Se abbiamo un URL dell'immagine profilo, scaricala e salvala su Cloudflare R2
          if (originalProfileImageUrl.isNotEmpty) {
            print('Original profile image URL: $originalProfileImageUrl');
            
            try {
              // Scarica l'immagine e salvala su Cloudflare R2
              final cloudflareProfileImageUrl = await _downloadAndUploadProfileImage(originalProfileImageUrl, instagramUserId);
              
              if (cloudflareProfileImageUrl != null) {
                profileImageUrl = cloudflareProfileImageUrl;
                print('Profile image saved to Cloudflare R2: $profileImageUrl');
              } else {
                // Se il salvataggio su Cloudflare fallisce, usa l'URL originale
                profileImageUrl = originalProfileImageUrl;
                print('Failed to save profile image to Cloudflare R2, using original URL');
              }
            } catch (e) {
              print('Error saving profile image to Cloudflare R2: $e');
              // In caso di errore, usa l'URL originale
              profileImageUrl = originalProfileImageUrl;
            }
          }
        }
      } catch (e) {
        print('Error getting profile info: $e');
      }
      
      // Clear pending auth state
      await _database.child('users/${user.uid}/instagram_pending_auth').remove();
      
      // Controlla se esiste già un account con lo stesso username
      String? existingAccountId;
      try {
        final existingAccountsSnapshot = await _database.child('users/${user.uid}/instagram').get();
        if (existingAccountsSnapshot.exists && existingAccountsSnapshot.value is Map) {
          final existingAccounts = existingAccountsSnapshot.value as Map<dynamic, dynamic>;
          for (final entry in existingAccounts.entries) {
            if (entry.value is Map) {
              final accountData = entry.value as Map<dynamic, dynamic>;
              if (accountData['username'] == userData['username']) {
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
        'username': userData['username'],
        'display_name': userData['username'],
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'last_sync': DateTime.now().millisecondsSinceEpoch,
        'status': 'active',
        'access_token': accessToken,
        'token_expires_in': longLivedTokenData['expires_in'] ?? 0,
        'user_id': instagramUserId,
        'profile_image_url': profileImageUrl,
        'followers_count': followersCount,
        'media_count': userData['media_count'] ?? 0,
        'account_type': 'BUSINESS',
        'permissions': '',
        'is_business_account': true,
        'biography': userData['biography'] ?? '',
        'website': userData['website'] ?? '',
        // AGGIUNTO: data di accesso tramite Instagram
        'instagram_connected_at': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Salva o aggiorna l'account
      if (existingAccountId != null) {
        // Aggiorna l'account esistente
        await _database.child('users/${user.uid}/instagram/$existingAccountId').update(accountData);
        print('Updated existing Instagram account: $existingAccountId');
      } else {
        // Crea nuovo account
        await _database.child('users/${user.uid}/instagram/$instagramUserId').set(accountData);
        print('Created new Instagram account: $instagramUserId');
      }

      await _loadAccounts();

      // SnackBar removed as requested
    } catch (e) {
      print('Error exchanging code for token: $e');
      // SnackBar removed as requested
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorDebugDialog(String title, String errorResponse) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'API Response:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  errorResponse,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Troubleshooting:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('1. Verify that your app is properly configured in the Facebook Developer Console'),
              const Text('2. Check that the redirect URI matches exactly what is configured in the app'),
              const Text('3. Ensure you are using the correct app ID and secret'),
              const Text('4. Verify that the requested scopes are approved for your app'),
              const SizedBox(height: 16),
              const Text(
                'Common Issues:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('• "invalid platform app" - App not properly configured in Facebook Developer Console'),
              const Text('• "invalid redirect_uri" - Redirect URI does not match what is configured'),
              const Text('• "invalid scope" - Requested permissions not approved for your app'),
              const Text('• "invalid client" - App ID or secret is incorrect'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showFacebookDeveloperConsoleInstructions();
                },
                child: const Text('View Facebook Developer Console Instructions'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showFacebookDeveloperConsoleInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Facebook Developer Console Setup'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Follow these steps to properly configure your Instagram app:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('1. Go to https://developers.facebook.com/'),
              const Text('2. Select your app or create a new one'),
              const Text('3. Go to "Instagram Basic Display" in the left menu'),
              const Text('4. Under "Client OAuth Settings":'),
              Text('   • Add the redirect URI: $_redirectUri'),
              const Text('   • Make sure "Deauthorize Callback URL" is set'),
              const Text('   • Make sure "Data Deletion Request URL" is set'),
              const Text('5. Under "Basic Display":'),
              const Text('   • Add your app\'s privacy policy URL'),
              const Text('   • Add your app\'s terms of service URL'),
              const Text('   • Add your app\'s app icon'),
              const Text('6. Under "User Token Generator":'),
              const Text('   • Add a test user (your Instagram account)'),
              const Text('   • Generate a token to test the connection'),
              const SizedBox(height: 16),
              const Text(
                'Note: Instagram only accepts HTTPS URLs as redirect URIs. ' +
                'We\'re using a redirect proxy page at viralyst-redirecturi.netlify.app ' +
                'that receives the Instagram redirect and then sends users back to the app ' +
                'using the viralyst:// custom scheme.',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeAccount(String accountId) async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _database.child('users/${user.uid}/instagram/$accountId').update({
        'status': 'inactive',
      });

      await _loadAccounts();

      // SnackBar removed as requested
    } catch (e) {
      print('Error removing account: $e');
      // SnackBar removed as requested
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _reactivateAccount(String accountId) async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _database.child('users/${user.uid}/instagram/$accountId').update({
        'status': 'active',
      });

      await _loadAccounts();

      // SnackBar removed as requested
    } catch (e) {
      print('Error reactivating account: $e');
      // SnackBar removed as requested
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
              'Are you sure you want to completely remove the Instagram account "${account['username']}" from your Viralyst account?',
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
                      'This will only remove the account from Viralyst. Your Instagram account will not be affected.',
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
      await _database.child('users/${user.uid}/instagram/$accountId').remove();

      // Refresh the UI
      await _loadAccounts();

      // SnackBar removed as requested
    } catch (e) {
      print('Error removing account: $e');
      // SnackBar removed as requested
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Metodo per mostrare le opzioni di connessione Instagram
  void _showInstagramConnectionOptions() {
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
                  color: const Color(0xFFC13584).withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  'assets/loghi/logo_insta.png',
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
                      icon: const Icon(Icons.publish, color: Color(0xFFC13584)),
                      label: const Text('Basic Access'),
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
                        _connectInstagramAccount();
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
                            Text('• Perfect for business accounts NOT linked to a Facebook page.',
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
                      icon: const Icon(Icons.analytics, color: Color(0xFFC13584)),
                      label: const Text('Advanced Access'),
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
                        _connectInstagramViaFacebook();
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
                            Text('• Choose this ONLY if your business account is linked to a Facebook page.',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]),),
                            Text('• Required for those who want statistics and insights.',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]),),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // See how to connect tutorial link - stesso design del popup superiore
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        if (!_isPageConnectVideoInitialized) {
                          await _initializePageConnectVideo();
                        }
                        if (_isPageConnectVideoInitialized && _pageConnectVideoController != null) {
                          _pageConnectVideoController!.play();
                          _showPageConnectVideoFullscreen();
                        }
                      },
                      child: Text(
                        'See how to connect Instagram account to Facebook page',
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                        ),
                        textAlign: TextAlign.center,
                      ),
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

  // Ripristino del metodo di connessione Instagram diretto (dal file 7)
  Future<void> _connectInstagramAccount() async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Save pending auth state
      await _database.child('users/${user.uid}/instagram_pending_auth').set({
        'status': 'pending',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Avvia direttamente l'autenticazione Instagram senza dialoghi intermedi
      await _startInstagramAuth();
    } catch (e) {
      print('Error connecting Instagram account: $e');
      // SnackBar removed as requested
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startInstagramAuth() async {
    try {
      setState(() => _isLoading = true);

      // Must use HTTPS URL for Instagram API configuration
      // Important: Use EXACTLY the same redirect_uri in both auth request and token exchange
      // Usiamo la variabile di classe che include lo slash finale
      final redirectUri = _redirectUri;
      
      final authUrl = Uri.parse(
        'https://www.instagram.com/oauth/authorize'
        '?enable_fb_login=0'
        '&force_authentication=1'
        '&client_id=$_instagramAppId'
        '&redirect_uri=$redirectUri'
        '&response_type=code'
        '&scope=$_instagramBusinessScopes'
      );

      print('Instagram Auth URL: $authUrl');
      print('Using redirect URI: $redirectUri');

      // SnackBar removed as requested

      // Lancia il browser esterno per l'autenticazione
      if (await canLaunchUrl(authUrl)) {
        await launchUrl(
          authUrl,
          mode: LaunchMode.externalApplication,
        );
      } else {
        // Fall back to WebView if direct launch isn't possible
        if (mounted) {
          _showWebViewDialog(authUrl.toString());
        }
      }
    } catch (e) {
      print('Error starting Instagram auth: $e');
      // SnackBar removed as requested
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showInstagramAccessPrompt([Map<String, dynamic>? account]) {
    if (account != null && account.containsKey('access_token') && account['access_token'] != null && account['access_token'].toString().isNotEmpty) {
      // Non mostrare il popup se il token è presente
      return;
    }
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
                        color: Color(0xFFC13584).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.info_outline,
                        size: 24,
                        color: Color(0xFFC13584),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 16),
                
                // Title
                Text(
                  'Instagram Access Required',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                
                SizedBox(height: 8),
                
                // Subtitle
                Text(
                  'To publish content on your Instagram account, you need to complete direct Instagram access.',
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
                    color: Color(0xFFC13584).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color(0xFFC13584).withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: Color(0xFFC13584),
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This operation takes only a few seconds',
                          style: TextStyle(
                            color: Color(0xFFC13584),
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
                      _startInstagramAuth();
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

  // Initialize tutorial video controller
  Future<void> _initializeTutorialVideo() async {
    try {
      print('Initializing Instagram tutorial video...');
      _tutorialVideoController = VideoPlayerController.asset('assets/animations/tutorial/instabusiness.mp4');
      await _tutorialVideoController!.initialize();
      _tutorialVideoController!.setLooping(true);
      _tutorialVideoController!.setVolume(0.0); // Mute per il tutorial
      
      print('Instagram tutorial video initialized successfully');
      print('Video duration: ${_tutorialVideoController!.value.duration}');
      print('Video size: ${_tutorialVideoController!.value.size}');
      
      // Aggiungi listener per monitorare lo stato del video
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
  
  // Initialize page-connect tutorial video controller
  Future<void> _initializePageConnectVideo() async {
    try {
      print('Initializing Instagram page-connect tutorial video...');
      _pageConnectVideoController = VideoPlayerController.asset('assets/animations/tutorial/pageconnectinsta.mp4');
      await _pageConnectVideoController!.initialize();
      _pageConnectVideoController!.setLooping(true);
      _pageConnectVideoController!.setVolume(0.0);
      
      print('Page-connect tutorial video initialized successfully');
      print('Video duration: ${_pageConnectVideoController!.value.duration}');
      print('Video size: ${_pageConnectVideoController!.value.size}');
      
      _pageConnectVideoController!.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
      
      setState(() {
        _isPageConnectVideoInitialized = true;
      });
    } catch (e) {
      print('Error initializing page-connect tutorial video: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }
  
  // Show video in fullscreen
  void _showVideoFullscreen() {
    if (_tutorialVideoController != null && _isTutorialVideoInitialized) {
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
                
                // Bottom progress bar (seconds) - copiato da video_quick_view_page.dart
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
                              height: 30, // Altezza aumentata per migliore cliccabilità
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
                                        trackHeight: 8, // Track più alto per migliore visibilità
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
        // Ferma il video tutorial quando il dialog viene chiuso
        _tutorialVideoController?.pause();
        _tutorialVideoController?.seekTo(Duration.zero);
      });
    }
  }
  
  // Show page-connect video in fullscreen
  void _showPageConnectVideoFullscreen() {
    if (_pageConnectVideoController != null && _isPageConnectVideoInitialized) {
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
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    margin: const EdgeInsets.only(top: 24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.black,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: AspectRatio(
                        aspectRatio: 8 / 16,
                        child: VideoPlayer(_pageConnectVideoController!),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    child: AspectRatio(
                      aspectRatio: 8 / 16,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          if (_pageConnectVideoController == null) return;
                          if (_pageConnectVideoController!.value.isPlaying) {
                            await _pageConnectVideoController!.pause();
                          } else {
                            await _pageConnectVideoController!.play();
                          }
                          if (mounted) setState(() {});
                        },
                        onDoubleTap: () async {
                          if (_pageConnectVideoController == null) return;
                          await _pageConnectVideoController!.seekTo(Duration.zero);
                          await _pageConnectVideoController!.play();
                        },
                        child: AnimatedOpacity(
                          opacity: _pageConnectVideoController!.value.isPlaying ? 0.0 : 1.0,
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
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: _pageConnectVideoController!,
                    builder: (context, value, child) {
                      final currentMs = value.position.inMilliseconds.toDouble();
                      final durationMs = (value.duration?.inMilliseconds.toDouble() ?? 1.0);
                      final max = durationMs > 0 ? durationMs : 1.0;
                      final clamped = currentMs.clamp(0.0, max);
                      final currentMinutes = (currentMs / 60000).floor();
                      final currentSeconds = ((currentMs % 60000) / 1000).floor();
                      final totalMinutes = (durationMs / 60000).floor();
                      final totalSeconds = ((durationMs % 60000) / 1000).floor();
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            Container(
                              height: 30,
                              child: Row(
                                children: [
                                  Text(
                                    '${currentMinutes.toString().padLeft(2, '0')}:${currentSeconds.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withOpacity(0.8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
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
                                          _pageConnectVideoController?.seekTo(Duration(milliseconds: v.toInt()));
                                        },
                                      ),
                                    ),
                                  ),
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
        _pageConnectVideoController?.pause();
        _pageConnectVideoController?.seekTo(Duration.zero);
      });
    }
  }

  void _showInstagramAdvancedAccessPrompt([Map<String, dynamic>? account]) {
    if (account != null && account.containsKey('facebook_access_token') && account['facebook_access_token'] != null && account['facebook_access_token'].toString().isNotEmpty) {
      // Non mostrare il popup se il token è presente
      return;
    }
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
                        color: Color(0xFFC13584).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.analytics_outlined,
                        size: 24,
                        color: Color(0xFFC13584),
                      ),
                    ),
                    // Close button (X)
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 20,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 16),
                
                // Title
                Text(
                  'Instagram Analytics Access',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                
                SizedBox(height: 8),
                
                // Subtitle
                Text(
                  'To view analytics and insights for your Instagram account, you need to complete advanced access.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                SizedBox(height: 12),
                
                // Reassurance box
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.green.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You can continue publishing with basic access',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 12),
                
                // Important warning box
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        color: Colors.orange,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Proceed ONLY if your Instagram account is linked to a Facebook page',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 12),
                
                // See how tutorial link - centrato e più vicino al box
                Center(
                  child: GestureDetector(
                    onTap: () async {
                      if (!_isPageConnectVideoInitialized) {
                        await _initializePageConnectVideo();
                      }
                      if (_isPageConnectVideoInitialized && _pageConnectVideoController != null) {
                        _pageConnectVideoController!.play();
                        _showPageConnectVideoFullscreen();
                      }
                    },
                    child: Text(
                      'See how to connect Instagram account to Facebook page',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                
                SizedBox(height: 20),
                
                // Action buttons
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _connectInstagramViaFacebook();
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
        // Effetto vetro semi-trasparente opaco
        color: theme.brightness == Brightness.dark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
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
                                  ? Color(0xFFC13584).withOpacity(0.2)
                                  : Color(0xFFC13584).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Image.asset(
                              'assets/loghi/logo_insta.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                            ),
          ),
          const SizedBox(width: 12),
                Text(
                              'Instagram Accounts',
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
                          color: Color(0xFFC13584), // Instagram purple color
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
                        'Manage your Instagram accounts and track their performance.',
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
            ),
            // Improved tab bar - more compact and elegant
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Container(
                height: 36, // Reduced height
                decoration: BoxDecoration(
                  // Effetto vetro semi-trasparente opaco
                  color: theme.brightness == Brightness.dark 
                      ? Colors.white.withOpacity(0.15) 
                      : Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(30),
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
                          Color(0xFFC13584), // Instagram gradient start
                          Color(0xFFE1306C), // Instagram gradient middle
                          Color(0xFFF56040), // Instagram gradient end
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFC13584).withOpacity(0.3),
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
                                            ? Color(0xFFC13584).withOpacity(0.2)
                                            : Color(0xFFC13584).withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Image.asset(
                                          'assets/loghi/logo_insta.png',
                                          width: 64,
                                          height: 64,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                    Text(
                                        'No Active Instagram Accounts',
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
                                        'Connect your Instagram account or reactivate it',
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
                                            ? Color(0xFFC13584).withOpacity(0.2)
                                            : Color(0xFFC13584).withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Image.asset(
                                          'assets/loghi/logo_insta.png',
                                          width: 64,
                                          height: 64,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                    Text(
                                        'No Inactive Instagram Accounts',
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
        shadowColor: Color(0xFFC13584).withOpacity(0.3),
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        child: Container(
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
            borderRadius: BorderRadius.circular(30),
          ),
          child: FloatingActionButton.extended(
           onPressed: _showInstagramConnectionOptions,
            heroTag: 'instagram_fab',
            icon: const Icon(Icons.add, size: 18),
                label: const Text('Connect Instagram Account'),
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
      bottomNavigationBar: null,
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
          borderRadius: BorderRadius.circular(20),
          // Effetto vetro semi-trasparente opaco
          color: theme.brightness == Brightness.dark 
              ? Colors.white.withOpacity(0.15) 
              : Colors.white.withOpacity(0.25),
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
                    'description': 'Instagram Account',
                },
                platform: 'instagram',
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
                                color: Color(0xFFC13584).withOpacity(0.2),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFFC13584).withOpacity(0.1),
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
                              color: Color(0xFFC13584).withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Color(0xFFC13584).withOpacity(0.2),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.camera_alt,
                              size: 32,
                              color: Color(0xFFC13584),
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
                          account['displayName'],
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
                        color: Color(0xFFC13584),
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
                    
                    // Badge informativo per account attivi senza access_token
                    if (isActive && !(account.containsKey('access_token') && account['access_token'] != null && account['access_token'].toString().isNotEmpty))
                      GestureDetector(
                        onTap: () => _showInstagramAccessPrompt(account),
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
                      
                    // Badge informativo per account attivi senza facebook_access_token (Advanced Access)
                    if (isActive && 
                        (account.containsKey('access_token') && account['access_token'] != null && account['access_token'].toString().isNotEmpty) &&
                        (!account.containsKey('facebook_access_token') || account['facebook_access_token'] == null || account['facebook_access_token'].toString().isEmpty))
                      GestureDetector(
                        onTap: () => _showInstagramAdvancedAccessPrompt(account),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Color(0xFFC13584).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Color(0xFFC13584).withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 12,
                                color: Color(0xFFC13584),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'ANALYTICS',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFC13584),
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
        // Effetto vetro semi-trasparente opaco
        color: theme.brightness == Brightness.dark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
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
                            Color(0xFFC13584),
                            Color(0xFFE1306C),
                            Color(0xFFF56040),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds);
                      },
                      child: const Text(
                        'Instagram',
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
              // Info button for tutorial
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _showTutorialBottomSheet,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Color(0xFFC13584).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Color(0xFFC13584).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Color(0xFFC13584),
                      ),
                    ),
                  ),
                ),
              ),
              // Accounts badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark 
                      ? Color(0xFFC13584).withOpacity(0.2)
                      : Color(0xFFC13584).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: theme.brightness == Brightness.dark 
                        ? Color(0xFFC13584).withOpacity(0.4)
                        : Color(0xFFC13584).withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: 14,
                      color: Color(0xFFC13584),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Accounts',
                      style: TextStyle(
                        color: Color(0xFFC13584),
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
                  ? Color(0xFFC13584).withOpacity(0.2)
                  : Color(0xFFC13584).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: Color(0xFFC13584),
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

  Widget _buildProfileImage(String? imageUrl, double size, Color borderColor, IconData fallbackIcon) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        border: Border.all(
          color: borderColor,
          width: 2,
        ),
      ),
      child: ClipOval(
        child: imageUrl?.isNotEmpty == true
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  print('Error loading Instagram image from $imageUrl: $error');
                  return Icon(
                    fallbackIcon,
                    color: Theme.of(context).colorScheme.primary,
                    size: size * 0.5,
                  );
                },
              )
            : Icon(
                fallbackIcon,
                color: Theme.of(context).colorScheme.primary,
                size: size * 0.5,
              ),
      ),
    );
  }

  // Play tutorial video when info section opens
  void _playTutorialVideo() {
    print('Attempting to play tutorial video...');
    print('Controller exists: ${_tutorialVideoController != null}');
    print('Video initialized: $_isTutorialVideoInitialized');
    
    if (_tutorialVideoController != null && _isTutorialVideoInitialized) {
      try {
        _tutorialVideoController!.play();
        print('Tutorial video started playing');
      } catch (e) {
        print('Error playing tutorial video: $e');
      }
    } else {
      print('Cannot play video: controller or initialization issue');
      // Se il video non è inizializzato, prova a reinizializzarlo
      if (_tutorialVideoController == null) {
        print('Re-initializing video controller...');
        _initializeTutorialVideo().then((_) {
          if (_isTutorialVideoInitialized && _tutorialVideoController != null) {
            _tutorialVideoController!.play();
            print('Video started after re-initialization');
          }
        });
      }
    }
  }
  
  // Pause tutorial video when info section closes
  void _pauseTutorialVideo() {
    if (_tutorialVideoController != null && _isTutorialVideoInitialized) {
      _tutorialVideoController!.pause();
      _tutorialVideoController!.seekTo(Duration.zero);
    }
  }

  // Show tutorial bottom sheet
  void _showTutorialBottomSheet() {
    // Avvia il video quando si apre la bottom sheet
    _playTutorialVideo();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          height: MediaQuery.of(context).size.height * 0.80, // Aperta all'80% dell'altezza dello schermo
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark ? Colors.grey[900]! : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(25),
              topRight: Radius.circular(25),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: Text(
                    "It's not that hard",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16), // Spazio ridotto
              // Video tutorial
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                                             // Video container
                       Center(
                         child: Container(
                           width: 190, // Aumentato da 160 a 220 per video più grande
                           decoration: BoxDecoration(
                             borderRadius: BorderRadius.circular(16),
                             border: Border.all(
                               color: Color(0xFFC13584).withOpacity(0.3),
                               width: 2,
                             ),
                             boxShadow: [
                               BoxShadow(
                                 color: Color(0xFFC13584).withOpacity(0.1),
                                 blurRadius: 20,
                                 spreadRadius: 5,
                                 offset: const Offset(0, 10),
                               ),
                             ],
                           ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: AspectRatio(
                              aspectRatio: 8 / 16, // Cambiato da 9:16 a 8:16 per video più stretto
                              child: _isTutorialVideoInitialized && _tutorialVideoController != null
                                  ? GestureDetector(
                                      onTap: _showVideoFullscreen,
                                      child: Stack(
                                        children: [
                                          VideoPlayer(_tutorialVideoController!),
                                        ],
                                      ),
                                    )
                                  : Container(
                                      decoration: BoxDecoration(
                                        color: theme.brightness == Brightness.dark ? Colors.grey[800]! : Colors.grey[100],
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Instagram Tutorial',
                                            style: TextStyle(
                                              color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                                              fontSize: 14, // Testo più piccolo
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Loading...',
                                            style: TextStyle(
                                              color: theme.brightness == Brightness.dark ? Colors.grey[500] : Colors.grey[500],
                                              fontSize: 12, // Testo più piccolo
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16), // Spazio ridotto
                                             // Description
                       Text(
                         'To connect Instagram \nyou need a Business account',
                         textAlign: TextAlign.center,
                         style: TextStyle(
                           fontSize: 16, // Font più grande per il messaggio principale
                           color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                           fontWeight: FontWeight.w600,
                           height: 1.3,
                         ),
                       ),
                                             const SizedBox(height: 8),
                       Text(
                         'It takes just 30 seconds to transform your Instagram account into a Business account',
                         textAlign: TextAlign.center,
                         style: TextStyle(
                           fontSize: 12, // Font più piccolo per il messaggio secondario
                           color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                           height: 1.3,
                         ),
                       ),
                       const SizedBox(height: 4), // Ridotto da 24 a 4 pixel (20 pixel in meno)
                     ],
                   ),
                 ),
               ),
               // Close button
               Padding(
                 padding: const EdgeInsets.all(16), // Padding ridotto
                child: SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFFC13584), // Instagram purple
                          Color(0xFFE1306C), // Instagram gradient middle
                          Color(0xFFF56040), // Instagram gradient end
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: () async {
                        _pauseTutorialVideo(); // Pausa il video quando si chiude
                        
                        // Apri Instagram app o sito web
                        final instagramUrl = Uri.parse('https://www.instagram.com');
                        if (await canLaunchUrl(instagramUrl)) {
                          await launchUrl(
                            instagramUrl,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                        
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12), // Padding verticale ridotto
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.open_in_new,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Open Instagram',
                            style: TextStyle(
                              fontSize: 14, // Testo più piccolo
                              fontWeight: FontWeight.w600,
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
        );
      },
    ).whenComplete(() {
      // Ferma il video tutorial quando la bottom sheet viene chiusa
      _pauseTutorialVideo();
    });
  }
} 