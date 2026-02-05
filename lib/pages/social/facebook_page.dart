import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert' show json, utf8, jsonDecode, jsonEncode;
import 'dart:io' show Platform;
import 'package:url_launcher/url_launcher.dart';
import '../settings_page.dart';
import '../profile_page.dart';
import './social_account_details_page.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:intl/intl.dart';

class FacebookPage extends StatefulWidget {
  final bool autoConnect;
  
  const FacebookPage({super.key, this.autoConnect = false});

  @override
  State<FacebookPage> createState() => _FacebookPageState();
}

class _FacebookPageState extends State<FacebookPage> with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  bool _isLoading = true;
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _inactiveAccounts = [];
  int _currentTabIndex = 0;
  bool _showInfo = false;
  User? _currentUser;
  final GlobalKey<AnimatedListState> _activeListKey = GlobalKey<AnimatedListState>();
  StreamSubscription? _linkSubscription;
  late TabController _tabController;
  
  // Animation controller for info section
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  // Facebook Business API scopes richiesti per account professionali
  // Basati su VEDI.md, includiamo tutti i permessi necessari per la gestione di pagine business 
  // e per la pubblicazione di contenuti su Instagram
  final List<String> _facebookPermissions = [
    'pages_show_list',
    'pages_read_engagement',
    'pages_manage_posts',
    'read_insights',
    'instagram_basic',
    'instagram_content_publish',
    'instagram_manage_comments',
    'instagram_manage_insights',
  ];

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
    
    _loadAccounts();
    _initDeepLinkHandling();
    
    // Avvia automaticamente il processo di connessione se richiesto
    if (widget.autoConnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _connectFacebookAccount();
      });
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initDeepLinkHandling() async {
    print('Initializing Facebook deep link handling...');
    final appLinks = AppLinks();
    
    // Handle initial link
    final initialLink = await appLinks.getInitialAppLink();
    print('Initial link: $initialLink');
    if (initialLink != null) {
      _handleIncomingLink(initialLink.toString());
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
    print('Handling incoming link: $link');
    try {
      final uri = Uri.parse(link);
      print('Parsed URI: $uri');
      
      // Check if this is a Facebook callback
      if ((uri.scheme == 'https' && uri.host == 'viralyst.online' && uri.path == '/auth/facebook-callback') ||
          (uri.scheme == 'viralyst' && uri.host == 'auth' && uri.path == '/callback') ||
          (uri.scheme == 'fb1256861902462549')) {
        
        print('Detected Facebook callback, initiating Facebook login with flutter_facebook_auth');
        // Instead of extracting the code, we'll use the Flutter Facebook Auth package
        _connectFacebookAccount();
      } else {
        print('URI does not match any expected callback format: ${uri.toString()}');
      }
    } catch (e) {
      print('Error parsing incoming link: $e');
      // SnackBar rimossa come richiesto
    }
  }

  Future<void> _loadAccounts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final snapshot = await _database.child('users/${user.uid}/facebook').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final allAccounts = data.entries.map((entry) => {
              'id': entry.key,
              'name': entry.value['name'] ?? '',
              'displayName': entry.value['display_name'] ?? '',
              'email': entry.value['email'] ?? '',
              'createdAt': entry.value['created_at'] ?? 0,
              'lastSync': entry.value['last_sync'] ?? 0,
              'status': entry.value['status'] ?? 'active',
              'profileImageUrl': entry.value['profile_image_url'] ?? '',
              'followersCount': entry.value['followers_count'] ?? 0,
              'pageType': entry.value['page_type'] ?? '',
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

  // Metodo per scaricare l'immagine profilo da un URL e salvarla su Cloudflare R2
  Future<String?> _downloadAndUploadProfileImage(String imageUrl, String pageId) async {
    try {
      print('Downloading Facebook profile image from: $imageUrl');
      
      // Download dell'immagine
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        print('Failed to download Facebook image: ${response.statusCode}');
        return null;
      }
      
      final imageBytes = response.bodyBytes;
      print('Downloaded Facebook image size: ${imageBytes.length} bytes');
      
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
      final fileName = 'profilePictures/${pageId}.$extension';
      
      // Upload su Cloudflare R2
      final cloudflareUrl = await _uploadImageToCloudflareR2(imageBytes, fileName, contentType ?? 'image/jpeg');
      
      print('Facebook profile image uploaded to Cloudflare R2: $cloudflareUrl');
      return cloudflareUrl;
      
    } catch (e) {
      print('Error downloading and uploading Facebook profile image: $e');
      return null;
    }
  }
  
  // Metodo per uploadare un'immagine su Cloudflare R2
  Future<String> _uploadImageToCloudflareR2(Uint8List imageBytes, String fileName, String contentType) async {
    try {
      print('Uploading Facebook image to Cloudflare R2: $fileName');
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
        
        print('Facebook image uploaded successfully to Cloudflare R2');
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

  Future<void> _connectFacebookAccount() async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Forza il logout per permettere il cambio account
      await FacebookAuth.instance.logOut();
      print('Facebook logout completed to allow account switching');

      // Login with Facebook using flutter_facebook_auth
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: _facebookPermissions,
        loginBehavior: LoginBehavior.nativeWithFallback,
      );

      if (result.status == LoginStatus.success) {
        // Get the access token
        final AccessToken? accessToken = result.accessToken;
        
        if (accessToken == null) {
          throw Exception('Failed to get access token');
        }
        
        print('Successfully obtained FB access token: ${accessToken.token}');
        
        // Get user's Facebook pages
        final pagesResponse = await http.get(
          Uri.parse(
            'https://graph.facebook.com/v18.0/me/accounts'
            '?access_token=${accessToken.token}'
          ),
        );

        if (pagesResponse.statusCode != 200) {
          throw Exception('Failed to get Facebook pages: ${pagesResponse.body}');
        }

        final pagesData = json.decode(pagesResponse.body);
        print('Pages response: $pagesData');
        final pages = pagesData['data'] as List;
        
        if (pages.isEmpty) {
          throw Exception('No Facebook pages found. You need a Facebook page to connect.');
        }

        // Process each page
        for (var page in pages) {
          final pageId = page['id'];
          final pageAccessToken = page['access_token'];
          final pageName = page['name'];
          final pageCategory = page['category'] ?? '';

          print('Processing FB Page: $pageName (ID: $pageId)');

          // Get page details with more fields per Facebook Business API
          final pageDetailsResponse = await http.get(
            Uri.parse(
              'https://graph.facebook.com/v18.0/$pageId'
              '?fields=fan_count,picture,instagram_business_account,connected_instagram_account,verification_status,category_list,followers_count'
              '&access_token=$pageAccessToken'
            ),
          );

          if (pageDetailsResponse.statusCode != 200) {
            print('Failed to get page details for $pageName: ${pageDetailsResponse.body}');
            continue;
          }

          final pageDetails = json.decode(pageDetailsResponse.body);
          print('Page details: $pageDetails');
          
          final followersCount = pageDetails['followers_count'] ?? pageDetails['fan_count'] ?? 0;
          final originalProfileImageUrl = pageDetails['picture']?['data']?['url'] ?? '';
          final instagramBusinessAccountId = pageDetails['instagram_business_account']?['id'];
          final connectedInstagramAccount = pageDetails['connected_instagram_account']?['id'];
          final verificationStatus = pageDetails['verification_status'] ?? 'not_verified';
          final categoryList = pageDetails['category_list'] ?? [];
          
          // Scarica e carica l'immagine profilo su Cloudflare R2 se disponibile
          String profileImageUrl = '';
          if (originalProfileImageUrl.isNotEmpty) {
            try {
              print('Downloading and uploading Facebook profile image for page: $pageName');
              final cloudflareProfileImageUrl = await _downloadAndUploadProfileImage(originalProfileImageUrl, pageId);
              if (cloudflareProfileImageUrl != null) {
                profileImageUrl = cloudflareProfileImageUrl;
                print('Facebook profile image saved to Cloudflare R2: $profileImageUrl');
              } else {
                // Fallback all'URL originale se il download/upload fallisce
                profileImageUrl = originalProfileImageUrl;
                print('Failed to upload to Cloudflare R2, using original URL: $profileImageUrl');
              }
            } catch (e) {
              print('Error processing Facebook profile image: $e');
              // Fallback all'URL originale in caso di errore
              profileImageUrl = originalProfileImageUrl;
            }
          }
          
          // Salva ulteriori dettagli per account business
          final pageData = {
            'name': pageName,
            'display_name': pageName,
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'last_sync': DateTime.now().millisecondsSinceEpoch,
            'status': 'active',
            'access_token': pageAccessToken,
            'page_id': pageId,
            'profile_image_url': profileImageUrl,
            'followers_count': followersCount,
            'page_type': pageCategory,
            'verification_status': verificationStatus,
            'category_list': categoryList,
          };
          
          // Aggiungi ID dell'account Instagram Business se disponibile
          if (instagramBusinessAccountId != null) {
            pageData['instagram_business_account_id'] = instagramBusinessAccountId;
            
            // Ottieni ulteriori dettagli sull'account Instagram collegato
            try {
              final igResponse = await http.get(
                Uri.parse(
                  'https://graph.facebook.com/v18.0/$instagramBusinessAccountId'
                  '?fields=username,profile_picture_url,followers_count,media_count'
                  '&access_token=$pageAccessToken'
                ),
              );
              
              if (igResponse.statusCode == 200) {
                final igData = json.decode(igResponse.body);
                print('Instagram business account data: $igData');
                
                // Gestisci l'immagine profilo Instagram Business
                String instagramProfileImageUrl = '';
                final originalInstagramProfileImageUrl = igData['profile_picture_url'] ?? '';
                
                if (originalInstagramProfileImageUrl.isNotEmpty) {
                  try {
                    print('Downloading and uploading Instagram Business profile image');
                    final cloudflareInstagramProfileImageUrl = await _downloadAndUploadProfileImage(
                      originalInstagramProfileImageUrl, 
                      'ig_${instagramBusinessAccountId}'
                    );
                    if (cloudflareInstagramProfileImageUrl != null) {
                      instagramProfileImageUrl = cloudflareInstagramProfileImageUrl;
                      print('Instagram Business profile image saved to Cloudflare R2: $instagramProfileImageUrl');
                    } else {
                      // Fallback all'URL originale se il download/upload fallisce
                      instagramProfileImageUrl = originalInstagramProfileImageUrl;
                      print('Failed to upload Instagram Business image to Cloudflare R2, using original URL');
                    }
                  } catch (e) {
                    print('Error processing Instagram Business profile image: $e');
                    // Fallback all'URL originale in caso di errore
                    instagramProfileImageUrl = originalInstagramProfileImageUrl;
                  }
                }
                
                pageData['instagram_username'] = igData['username'];
                pageData['instagram_profile_picture_url'] = instagramProfileImageUrl;
                pageData['instagram_followers_count'] = igData['followers_count'];
                pageData['instagram_media_count'] = igData['media_count'];
              }
            } catch (e) {
              print('Error getting Instagram business account details: $e');
            }
          }

          // Save Facebook page to Firebase
          await _database.child('users/${user.uid}/facebook/$pageId').set(pageData);
        }
        
        await _loadAccounts();

        if (mounted) {
          // SnackBar rimossa come richiesto
        }
      } else if (result.status == LoginStatus.cancelled) {
        print('Facebook login cancelled by user');
        if (mounted) {
          // SnackBar rimossa come richiesto
        }
      } else {
        print('Facebook login failed: ${result.message}');
        throw Exception('Facebook login failed: ${result.message}');
      }
    } catch (e) {
      print('Error connecting Facebook account: $e');
      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } finally {
      // Ensure logout at the end of the flow so user can switch account next time
      try {
        await FacebookAuth.instance.logOut();
        print('Facebook session logged out at the end of connection flow');
      } catch (e) {
        print('Warning: failed to logout Facebook session at end of flow: $e');
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _removeAccount(String accountId) async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _database.child('users/${user.uid}/facebook/$accountId').update({
        'status': 'inactive',
      });

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

  Future<void> _reactivateAccount(String accountId) async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _database.child('users/${user.uid}/facebook/$accountId').update({
        'status': 'active',
      });

      await _loadAccounts();

      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } catch (e) {
      print('Error reactivating account: $e');
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
              'Remove Page',
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
              'Are you sure you want to completely remove the Facebook page "${account['displayName'] ?? account['name']}" from your Fluzar account?',
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
                      'This will only remove the page from Fluzar. Your Facebook page will not be affected.',
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
      await _database.child('users/${user.uid}/facebook/$accountId').remove();

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
                                  ? Color(0xFF1877F2).withOpacity(0.2)
                                  : Color(0xFF1877F2).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Image.asset(
                              'assets/loghi/logo_facebook.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Facebook Pages',
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
                          color: Color(0xFF1877F2), // Facebook blue
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
                            'Manage your Facebook accounts and track their performance.',
                            Icons.account_box,
                          ),
                          _buildInfoItem(
                            'Interactive Details',
                            'Click on any account to view the videos published with Fluzar.',
                            Icons.touch_app,
                          ),
                          _buildInfoItem(
                            'Account Switching',
                            'To connect a different Facebook account, you need to logout from the Facebook app and then reconnect here in Fluzar.',
                            Icons.swap_horiz,
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
                      color: Color(0xFF1877F2), // Facebook blue
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF1877F2).withOpacity(0.3),
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
                      Tab(text: 'Active Pages'),
                      Tab(text: 'Inactive Pages'),
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
                        // Active Pages Tab
                        _accounts.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: theme.brightness == Brightness.dark 
                                            ? Color(0xFF1877F2).withOpacity(0.2)
                                            : Color(0xFF1877F2).withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Image.asset(
                                        'assets/loghi/logo_facebook.png',
                                        width: 64,
                                        height: 64,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      'No Active Facebook Pages',
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
                                        'Connect your Facebook page to get started',
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
                        // Inactive Pages Tab
                        _inactiveAccounts.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: theme.brightness == Brightness.dark 
                                            ? Color(0xFF1877F2).withOpacity(0.2)
                                            : Color(0xFF1877F2).withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Image.asset(
                                        'assets/loghi/logo_facebook.png',
                                        width: 64,
                                        height: 64,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      'No Inactive Facebook Pages',
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
                                        'Deactivated pages will appear here',
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
        shadowColor: Color(0xFF1877F2).withOpacity(0.3),
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          decoration: BoxDecoration(
            color: Color(0xFF1877F2), // Facebook blue
            borderRadius: BorderRadius.circular(30),
          ),
          child: FloatingActionButton.extended(
            onPressed: _connectFacebookAccount,
            heroTag: 'facebook_fab',
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Connect Facebook Page'),
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
            if (isActive) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SocialAccountDetailsPage(
                    account: {
                      'id': account['id'],
                      'username': account['name'],
                      'displayName': account['displayName'],
                      'profileImageUrl': account['profileImageUrl'],
                      'description': account['pageType'] ?? '',
                      'followersCount': account['followersCount'] ?? 0,
                    },
                    platform: 'facebook',
                  ),
                ),
              );
            }
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
                        _buildProfileImage(
                          account['profileImageUrl'], 
                          70, 
                          Color(0xFF1877F2).withOpacity(0.2), 
                          Icons.facebook
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
                          Text(
                            account['displayName'] ?? account['name'],
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if (account['pageType']?.isNotEmpty ?? false) 
                            const SizedBox(height: 4),
                          if (account['pageType']?.isNotEmpty ?? false)
                            Row(
                              children: [
                                Icon(
                                  Icons.category,
                                  size: 14,
                                  color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  account['pageType'],
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
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
                                isActive
                                    ? 'Connected ${_formatDate(account['createdAt'])}'
                                    : 'Disconnected ${_formatDate(account['lastSync'])}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          if (account['followersCount'] > 0 && isActive) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.people_outline,
                                  size: 14,
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${account['followersCount']} followers',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Action button
                    isActive ? 
                    IconButton(
                      icon: Icon(
                        Icons.remove_circle_outline,
                        color: Color(0xFF1877F2),
                        size: 22,
                      ),
                      tooltip: 'Deactivate Page',
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
                          tooltip: 'Delete Page',
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
                            Color(0xFF1877F2),
                            Color(0xFF0E62C7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds);
                      },
                      child: const Text(
                        'Facebook',
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
              // Info button for account switching help
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _showInfoBottomSheet,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Color(0xFF1877F2).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Color(0xFF1877F2).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Color(0xFF1877F2),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark 
                      ? Color(0xFF1877F2).withOpacity(0.2)
                      : Color(0xFF1877F2).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: theme.brightness == Brightness.dark 
                        ? Color(0xFF1877F2).withOpacity(0.4)
                        : Color(0xFF1877F2).withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.pages_outlined,
                      size: 14,
                      color: Color(0xFF1877F2),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Pages',
                      style: TextStyle(
                        color: Color(0xFF1877F2),
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

  Widget _buildProfileImage(String? imageUrl, double size, Color borderColor, IconData fallbackIcon) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.brightness == Brightness.dark 
                ? Color(0xFF1877F2).withOpacity(0.2)
                : Color(0xFF1877F2).withOpacity(0.1),
            border: Border.all(
              color: borderColor,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.brightness == Brightness.dark 
                    ? Color(0xFF1877F2).withOpacity(0.2)
                    : Color(0xFF1877F2).withOpacity(0.1),
                blurRadius: 8,
                spreadRadius: 1,
                offset: Offset(0, 2),
              ),
            ],
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
                      print('Error loading Facebook image from $imageUrl: $error');
                      return Icon(
                        fallbackIcon,
                        color: Color(0xFF1877F2),
                        size: size * 0.5,
                      );
                    },
                  )
                : Icon(
                    fallbackIcon,
                    color: Color(0xFF1877F2),
                    size: size * 0.5,
                  ),
          ),
        ),
      ],
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
                  ? Color(0xFF1877F2).withOpacity(0.2)
                  : Color(0xFF1877F2).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Color(0xFF1877F2),
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

  // Show info bottom sheet for account switching help
  void _showInfoBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          height: MediaQuery.of(context).size.height * 0.53,
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
                margin: const EdgeInsets.only(top: 12, bottom: 12),
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
                child: Text(
                  'Account Switching Help',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      // First instruction
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark 
                              ? Color(0xFF1877F2).withOpacity(0.1)
                              : Color(0xFF1877F2).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Color(0xFF1877F2).withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.logout,
                              size: 24,
                              color: Color(0xFF1877F2),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Step 1: Logout from Facebook',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'To connect a different Facebook account, you need to logout from the Facebook app first.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Second instruction
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark 
                              ? Color(0xFF1877F2).withOpacity(0.1)
                              : Color(0xFF1877F2).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Color(0xFF1877F2).withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.login,
                              size: 24,
                              color: Color(0xFF1877F2),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Step 2: Reconnect in Fluzar',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'After logging out from Facebook, come back to Fluzar and tap "Connect Facebook Page" to reconnect with your new account.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Open Facebook button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await _openFacebookApp();
                          },
                          icon: Image.asset(
                            'assets/loghi/logo_facebook.png',
                            width: 20,
                            height: 20,
                            fit: BoxFit.contain,
                          ),
                          label: const Text(
                            'Open Facebook',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF1877F2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Method to open Facebook app
  Future<void> _openFacebookApp() async {
    try {
      // Try to open Facebook app first
      const facebookAppUrl = 'fb://';
      const facebookWebUrl = 'https://www.facebook.com';
      
      if (await canLaunchUrl(Uri.parse(facebookAppUrl))) {
        await launchUrl(Uri.parse(facebookAppUrl));
      } else if (await canLaunchUrl(Uri.parse(facebookWebUrl))) {
        await launchUrl(Uri.parse(facebookWebUrl));
      } else {
        print('Could not launch Facebook app or website');
      }
    } catch (e) {
      print('Error opening Facebook: $e');
    }
  }
} 