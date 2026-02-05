import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert' show json, utf8, jsonDecode, jsonEncode, base64Url;
import 'dart:io' show Platform;
import 'dart:math' show min, Random;
import 'package:url_launcher/url_launcher.dart';
import '../settings_page.dart';
import '../profile_page.dart';
import './social_account_details_page.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:intl/intl.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class TikTokPage extends StatefulWidget {
  final bool autoConnect;
  
  const TikTokPage({super.key, this.autoConnect = false});

  @override
  State<TikTokPage> createState() => _TikTokPageState();
}

class _TikTokPageState extends State<TikTokPage> with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  bool _isLoading = true;
  // Flag per indicare se è in corso un'eliminazione
  bool _isDeleting = false;
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _inactiveAccounts = [];
  User? _currentUser;
  StreamSubscription? _linkSubscription;
  late TabController _tabController;
  
  // Animation controller for info section
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _showInfo = false;
  
  // Video player controller for tutorial
  VideoPlayerController? _tutorialVideoController;
  bool _isTutorialVideoInitialized = false;

  // TikTok API credentials - LIVE APP
  final String _clientKey = 'awfszvwmbv73a9u9';
  final String _clientSecret = 'A5JTgaY8v7BdNBegStGDJgQyw7wuEDWG';
  final String _redirectUri = 'https://viralystsupport.info/';
  
  // PKCE values (to be generated during authorization)
  String? _codeVerifier;
  String? _codeChallenge;
  
  // Scopes required for TikTok API
  final List<String> _tiktokScopes = [
    'user.info.basic',
    'user.info.stats',
    'video.list',
    'video.upload',
    'video.publish'
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
    
    // Assicuriamoci che i dati PKCE siano sempre puliti all'avvio
    _clearAllLocalAuthData();
    
    // Avvia automaticamente il processo di connessione se richiesto
    if (widget.autoConnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _connectTikTokAccount();
      });
    }
    
    // Mostra popup informativo TikTok in fase di test
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasShownTiktokInfo) {
        _hasShownTiktokInfo = true;
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
                    'TikTok Testing Phase',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'TikTok integration is currently in testing. For now, publishing to TikTok is NOT available.\n\nThis is only temporary: publishing to TikTok will be available soon.',
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
    
    // Initialize tutorial video controller
    _initializeTutorialVideo();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _tabController.dispose();
    _animationController.dispose();
    
    // Dispose tutorial video controller
    _tutorialVideoController?.dispose();
    
    // Pulisci tutti i dati di autenticazione anche quando la pagina viene chiusa
    _clearAllLocalAuthData();
    super.dispose();
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
                                  ? Colors.grey[800] 
                                  : Colors.black.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Image.asset(
                              'assets/loghi/logo_tiktok.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => 
                                Icon(Icons.video_library, size: 32, color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'TikTok Accounts',
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
                          color: const Color(0xFF00F2EA), // TikTok turchese
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
                            'Manage your TikTok accounts and track their performance.',
                            Icons.account_box,
                          ),
                          _buildInfoItem(
                            'Interactive Details',
                            'Click on any account to view the videos published with Fluzar.',
                            Icons.touch_app,
                          ),
                          _buildInfoItem(
                            'Video Publishing',
                            'Schedule and publish videos directly to your TikTok account.',
                            Icons.video_library,
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
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF00F2EA), // TikTok turchese
                          Color(0xFFFF0050), // TikTok rosa
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00F2EA).withOpacity(0.3),
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
                            ? _buildEmptyActiveAccountsState()
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
                            ? _buildEmptyInactiveAccountsState()
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
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF00F2EA), // TikTok turchese
              Color(0xFFFF0050), // TikTok rosa
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00F2EA).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: const Color(0xFFFF0050).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _connectTikTokAccount,
          heroTag: 'tiktok_fab',
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Connect TikTok Account'),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
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
                        return const LinearGradient(
                          colors: [
                            Color(0xFF00F2EA), // TikTok turchese
                            Color(0xFFFF0050), // TikTok rosa
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds);
                      },
                      child: const Text(
                        'TikTok',
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
            mainAxisSize: MainAxisSize.min,
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
                        color: const Color(0xFF00F2EA).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF00F2EA).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.info_outline,
                        size: 16,
                        color: const Color(0xFF00F2EA),
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
                      ? Colors.grey[800]! 
                      : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: theme.brightness == Brightness.dark 
                        ? Colors.grey[700]! 
                        : Colors.black.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.video_library_outlined,
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
                  ? Colors.grey[800]! 
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: const Color(0xFF00F2EA), // TikTok turchese
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

  Widget _buildEmptyActiveAccountsState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark 
                  ? Colors.grey[800]! 
                  : Colors.black.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/loghi/logo_tiktok.png',
              width: 64,
              height: 64,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => 
                Icon(Icons.video_library, size: 64, color: theme.brightness == Brightness.dark ? Colors.grey[500] : Colors.grey[400]),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Active TikTok Accounts',
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
              'Connect your TikTok account to get started',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyInactiveAccountsState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark 
                  ? Colors.grey[800]! 
                  : Colors.black.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/loghi/logo_tiktok.png',
              width: 64,
              height: 64,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => 
                Icon(Icons.video_library, size: 64, color: theme.brightness == Brightness.dark ? Colors.grey[500] : Colors.grey[400]),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Inactive TikTok Accounts',
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
                    'username': account['username'] ?? '',
                    'displayName': account['displayName'] ?? account['name'] ?? 'TikTok Account',
                    'profileImageUrl': account['profileImageUrl'] ?? '',
                    'profileImageLargeUrl': account['profileImageLargeUrl'] ?? '',
                    'followersCount': account['followersCount'] ?? 0,
                    'followingCount': account['followingCount'] ?? 0,
                    'videoCount': account['videoCount'] ?? 0,
                    'likesCount': account['likesCount'] ?? 0,
                    'isVerified': account['isVerified'] ?? false,
                    'bio': account['bio'] ?? '',
                    'profileDeepLink': account['profileDeepLink'] ?? '',
                    'description': account['bio'] ?? 'TikTok Account',
                    'openId': account['openId'] ?? '',
                  },
                  platform: 'tiktok',
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
                                color: const Color(0xFF00F2EA).withOpacity(0.2),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00F2EA).withOpacity(0.1),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00F2EA).withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF00F2EA).withOpacity(0.2),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.person,
                              size: 32,
                              color: Color(0xFF00F2EA),
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
                            account['displayName'] ?? account['name'] ?? account['username'] ?? 'TikTok Account',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (account['username'] != null && account['username'].isNotEmpty)
                            Row(
                              children: [
                                Icon(
                                  Icons.alternate_email,
                                  size: 14,
                                  color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '@${account['username']}',
                                  style: TextStyle(
                                    color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 6),
                          // Followers count
                          Row(
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 14,
                                color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${NumberFormat.compact().format(account['followersCount'] ?? 0)} followers',
                                style: TextStyle(
                                  color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Last sync date
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 14,
                                color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Last updated: ${_formatDate(account['lastSync'] ?? 0)}',
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
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.red, // Use standard red for deactivate
                        size: 22,
                      ),
                      tooltip: 'Deactivate Account',
                      onPressed: () => _removeAccount(account['id']),
                    ) :
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade700, // Darker red for delete
                        size: 22,
                      ),
                      tooltip: 'Delete Account',
                      onPressed: () => _showDeleteConfirmationDialog(account['id']),
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
                    
                    // Action button for inactive accounts
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          minimumSize: const Size(0, 32),
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

  void _showDeleteConfirmationDialog(String accountId) {
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
                color: Colors.red.withOpacity(0.1), // Standard red
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.warning_amber_rounded, 
                color: Colors.red.shade700, // Darker red
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
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
            const Text(
              'Are you sure you want to completely remove this TikTok account from your Fluzar account?',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
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
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'This will only remove the account from Fluzar. Your TikTok account will not be affected.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
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
              _permanentlyRemoveAccount(accountId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700, // Darker red
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  // Add this method to permanently remove the account from database
  Future<void> _permanentlyRemoveAccount(String accountId) async {
    try {
      // Imposta il flag di eliminazione
      _isDeleting = true;
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Prima recuperiamo l'account per fare una revoca del token
      final accountSnapshot = await _database.child('users/${user.uid}/tiktok/$accountId').get();
      if (accountSnapshot.exists) {
        final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
        final accessToken = accountData['access_token'] as String?;
        
        if (accessToken != null) {
          // Prova a revocare il token di accesso
          try {
            print('Revoking TikTok access token for account $accountId');
            await _revokeTikTokToken(accessToken);
          } catch (e) {
            // Se la revoca fallisce, continuiamo comunque con l'eliminazione
            print('Error revoking TikTok token: $e');
          }
        }
      }

      // Elimina completamente l'account da Firebase
      print('Completely removing TikTok account $accountId from Firebase');
      await _database.child('users/${user.uid}/tiktok/$accountId').remove();

      // Pulisci tutti i dati di autenticazione - importante per evitare riconnessioni
      _clearAllLocalAuthData();
      
      // Reinizializza il gestore di deep link per evitare problemi con link salvati
      await _initDeepLinkHandling();

      // Ricarica gli account dopo aver eliminato tutti i dati locali
      await _loadAccounts();

      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } catch (e) {
      print('Error removing account: $e');
      print('Stack trace: ${StackTrace.current}');
      // SnackBar rimossa come richiesto
    } finally {
      setState(() => _isLoading = false);
      // Resetta il flag di eliminazione
      _isDeleting = false;
    }
  }

  // Format date for display
  String _formatDate(int timestamp) {
    if (timestamp == 0) return 'never';
    
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }

  Future<void> _initDeepLinkHandling() async {
    // Cancella l'attuale subscription se esiste
    await _linkSubscription?.cancel();
    _linkSubscription = null;
    
    print('Initializing TikTok deep link handling... (re-initialized)');
    final appLinks = AppLinks();
    
    // Handle initial link - ma solo se non stiamo ricariando dopo un'eliminazione
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
      
      // Verifica se abbiamo appena eliminato un account
      // In tal caso, ignora il link per evitare riconnessioni
      if (_isDeleting) {
        print('Ignoring link because account deletion is in progress: $link');
        return;
      }
      
      if (_isLoading) {
        print('Ignoring link while loading/processing: $link');
        return;
      }
      
      // Check if this is a TikTok callback using a more flexible approach
      // This will handle both formats:
      // - viralyst://tiktok/callback (double slash)
      // - viralyst:///tiktok/callback (triple slash)
      if (uri.scheme == 'viralyst' && 
          (uri.host == 'tiktok' || uri.path.contains('tiktok')) && 
          (uri.path.endsWith('/callback') || uri.path.contains('callback'))) {
        print('Detected TikTok callback');
        
        // Extract token data or error
        final tokenDataString = uri.queryParameters['token_data'];
        final error = uri.queryParameters['error'];
        final errorDescription = uri.queryParameters['error_description'];
        
        if (tokenDataString != null) {
          print('Token data received');
          // Parse token data JSON
          Map<String, dynamic> tokenData = json.decode(Uri.decodeComponent(tokenDataString));
          
          // Process the token data
          _handleTokenData(tokenData);
        } else if (error != null) {
          print('Authorization error: $error, Description: $errorDescription');
          // SnackBar rimossa come richiesto
        }
      } else {
        print('URI does not match TikTok callback format: ${uri.toString()}');
      }
    } catch (e) {
      print('Error parsing incoming link: $e');
      // SnackBar rimossa come richiesto
    }
  }

  // Process token data received from the web redirect
  Future<void> _handleTokenData(Map<String, dynamic> tokenData) async {
    try {
      setState(() => _isLoading = true);
      
      print('Received token data: ${tokenData.toString()}');
      
      // Verifica se è già in corso un'operazione di eliminazione
      if (_isDeleting) {
        print('Ignoring token data because an account is being deleted');
        return;
      }
      
      // Properly cast values to correct types
      final accessToken = tokenData['access_token'] as String?;
      final openId = tokenData['open_id'] as String?;
      final refreshToken = tokenData['refresh_token'] as String?;
      final expiresIn = tokenData['expires_in'] is int ? tokenData['expires_in'] : int.tryParse(tokenData['expires_in']?.toString() ?? '0') ?? 0;
      final refreshExpiresIn = tokenData['refresh_expires_in'] is int ? tokenData['refresh_expires_in'] : int.tryParse(tokenData['refresh_expires_in']?.toString() ?? '0') ?? 0;
      final scope = tokenData['scope'] as String?;
      
      // Safely convert fields_info to Map<String, dynamic>
      Map<String, dynamic> fieldsInfo = {};
      if (tokenData['fields_info'] != null) {
        fieldsInfo = Map<String, dynamic>.from(tokenData['fields_info'] as Map);
      }
      
      if (accessToken == null || openId == null) {
        throw Exception('Invalid token data: missing access_token or open_id');
      }

      // Verifica se questo account esiste già - in tal caso, non fare nulla
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final accountSnapshot = await _database.child('users/${user.uid}/tiktok/$openId').get();
        if (accountSnapshot.exists) {
          print('Account with openId $openId already exists, skipping...');
          setState(() => _isLoading = false);
          return;
        }
      }

      print('Access token: ${accessToken.substring(0, min<int>(10, accessToken.length))}...');
      print('Open ID: $openId');
      print('Refresh token: ${refreshToken != null ? '${refreshToken.substring(0, min<int>(10, refreshToken.length))}...' : 'not provided'}');
      print('Token expires in: $expiresIn seconds');
      print('Refresh token expires in: $refreshExpiresIn seconds');
      print('Granted scopes: $scope');
      
      if (fieldsInfo.isNotEmpty) {
        print('Fields info received: $fieldsInfo');
      }
      
      // Fetch user profile with the access token
      await _fetchTikTokUserProfile(
        accessToken,
        openId,
        refreshToken,
        expiresIn,
        refreshExpiresIn,
        scope,
        fieldsInfo,
      );
      
      // Reload accounts list
      await _loadAccounts();
      
      if (mounted) {
        // SnackBar rimossa come richiesto
        
        // Rimuovo la navigazione di ritorno - l'utente rimane nella pagina TikTok
        // come funziona in Instagram
      }
    } catch (e) {
      print('Error processing token data: $e');
      print('Stack trace: ${StackTrace.current}');
      // SnackBar rimossa come richiesto
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Nuovo metodo per revocare il token TikTok
  Future<void> _revokeTikTokToken(String accessToken) async {
    try {
      // Usando la documentazione TikTok per revocare il token
      final response = await http.post(
        Uri.parse('https://open.tiktokapis.com/v2/oauth/revoke/'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'client_key': _clientKey,
          'client_secret': _clientSecret,
          'token': accessToken,
        },
      );

      if (response.statusCode == 200) {
        print('Token revoked successfully');
      } else {
        print('Failed to revoke token: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Exception when revoking token: $e');
      throw e;
    }
  }

  // Metodo per scaricare l'immagine profilo da un URL e salvarla su Cloudflare R2
  Future<String?> _downloadAndUploadProfileImage(String imageUrl, String openId) async {
    try {
      print('Downloading TikTok profile image from: $imageUrl');
      
      // Download dell'immagine
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        print('Failed to download TikTok image: ${response.statusCode}');
        return null;
      }
      
      final imageBytes = response.bodyBytes;
      print('Downloaded TikTok image size: ${imageBytes.length} bytes');
      
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
      final fileName = 'profilePictures/${openId}.$extension';
      
      // Upload su Cloudflare R2
      final cloudflareUrl = await _uploadImageToCloudflareR2(imageBytes, fileName, contentType ?? 'image/jpeg');
      
      print('TikTok profile image uploaded to Cloudflare R2: $cloudflareUrl');
      return cloudflareUrl;
      
    } catch (e) {
      print('Error downloading and uploading TikTok profile image: $e');
      return null;
    }
  }
  
  // Metodo per uploadare un'immagine su Cloudflare R2
  Future<String> _uploadImageToCloudflareR2(Uint8List imageBytes, String fileName, String contentType) async {
    try {
      print('Uploading TikTok image to Cloudflare R2: $fileName');
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
        
        print('TikTok image uploaded successfully to Cloudflare R2');
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
    // Implementation of _exchangeCodeForToken method
  }

  // Metodo per pulire TUTTI i dati di autenticazione memorizzati localmente
  void _clearAllLocalAuthData() {
    // Resetta le variabili PKCE
    _codeVerifier = null;
    _codeChallenge = null;
    
    // Pulisci tutte le variabili di stato che potrebbero contenere informazioni di autenticazione
    if (mounted) {
      setState(() {
        // Rimuovi qualsiasi dato di account che potrebbe causare riconnessioni automatiche
        _accounts = [];
        _inactiveAccounts = [];
      });
    }
    
    // Rimuovi eventuali preferenze condivise o storage locale
    // Questo è importante per evitare riconnessioni automatiche
    _clearSharedPreferences();
    
    print('CLEARED ALL local authentication data');
  }
  
  // Cancella eventuali dati memorizzati nelle shared preferences
  Future<void> _clearSharedPreferences() async {
    try {
      // Se usi shared_preferences, dovrai aggiungerlo alle dipendenze
      // final prefs = await SharedPreferences.getInstance();
      // await prefs.remove('tiktok_auth_data');
      // await prefs.remove('tiktok_token');
      
      print('Cleared any TikTok data from shared preferences');
    } catch (e) {
      print('Error clearing shared preferences: $e');
    }
  }

  Future<void> _removeAccount(String accountId) async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Update account status to inactive instead of removing it
      await _database.child('users/${user.uid}/tiktok/$accountId').update({
        'status': 'inactive',
      });

      // Reload accounts to update the UI
      await _loadAccounts();

      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } catch (e) {
      print('Error deactivating account: $e');
      print('Stack trace: ${StackTrace.current}');
      // SnackBar rimossa come richiesto
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _connectTikTokAccount() async {
    try {
      setState(() => _isLoading = true);

      // Pulisci eventuali dati precedenti per evitare problemi
      _clearConnectionData();

      // Generate PKCE code verifier and challenge
      _codeVerifier = _generateRandomString(128);
      _codeChallenge = _generateCodeChallenge(_codeVerifier!);
      
      print('Generated code verifier: $_codeVerifier');
      print('Generated code challenge: $_codeChallenge');

      // Ensure we're using the correct redirect URI
      final redirectUri = 'https://viralystsupport.info/';
      
      // Aggiungi un timestamp univoco allo state per evitare cache e riutilizzo
      final uniqueState = 'tiktok_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000000)}';
      print('Using unique state: $uniqueState');
      
      // Construct TikTok authorization URL - utilizziamo tutti gli scope richiesti
      final authUrl = Uri.https('www.tiktok.com', '/v2/auth/authorize/', {
        'client_key': _clientKey,
        'scope': _tiktokScopes.join(','),
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'code_challenge': _codeChallenge,
        'code_challenge_method': 'S256',
        'state': uniqueState,
        'prompt': 'consent', // Force showing consent screen even if previously authorized
        'disable_auto_auth': '1', // Force display of authorization page
      });
      
      print('Opening TikTok authorization URL: $authUrl');

      // Platform-specific handling
      if (await canLaunchUrl(authUrl)) {
        if (Platform.isIOS) {
          // On iOS, try to use Safari for better handling of Universal Links
          print('iOS platform detected, using Safari');
          await launchUrl(
            authUrl,
            mode: LaunchMode.externalApplication,
          );
        } else if (Platform.isAndroid) {
          // On Android, try different strategies
          try {
            // First try using Chrome Custom Tabs if available
            print('Android platform detected, using external browser');
            await launchUrl(
              authUrl,
              mode: LaunchMode.externalApplication,
            );
          } catch (e) {
            print('Failed to open in external browser: $e');
            // Fallback to in-app webview
            print('Falling back to in-app browser');
            await launchUrl(
              authUrl,
              mode: LaunchMode.inAppWebView,
              webViewConfiguration: const WebViewConfiguration(
                enableJavaScript: true,
                enableDomStorage: true,
              ),
            );
          }
        } else {
          // Default for other platforms
          print('Other platform detected, using external browser');
          await launchUrl(authUrl, mode: LaunchMode.externalApplication);
        }
      } else {
        throw Exception('Could not launch TikTok authorization URL');
      }
    } catch (e) {
      print('Error initiating TikTok authorization: $e');
      // SnackBar rimossa come richiesto
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Generate a random string for PKCE code verifier
  String _generateRandomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }

  // Generate code challenge from code verifier (for PKCE)
  String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  Future<void> _loadAccounts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      print('Loading TikTok accounts for user: ${user.uid}');
      final snapshot = await _database.child('users/${user.uid}/tiktok').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final allAccounts = data.entries.map((entry) => {
              'id': entry.key,
              'name': entry.value['name'] ?? '',
              'displayName': entry.value['display_name'] ?? '',
              'username': entry.value['username'] ?? '',
              'bio': entry.value['bio'] ?? '',
              'isVerified': entry.value['is_verified'] ?? false,
              'profileDeepLink': entry.value['profile_deep_link'] ?? '',
              'createdAt': entry.value['created_at'] ?? 0,
              'lastSync': entry.value['last_sync'] ?? 0,
              'status': entry.value['status'] ?? 'active',
              'profileImageUrl': entry.value['profile_image_url'] ?? '',
              'profileImageUrl100': entry.value['profile_image_url_100'] ?? '',
              'profileImageLargeUrl': entry.value['profile_image_large_url'] ?? '',
              'followersCount': entry.value['followers_count'] ?? 0,
              'followingCount': entry.value['following_count'] ?? 0,
              'videoCount': entry.value['video_count'] ?? 0,
              'likesCount': entry.value['likes_count'] ?? 0,
              'openId': entry.value['open_id'] ?? '',
              'unionId': entry.value['union_id'] ?? '',
              'scopes': entry.value['scopes'] ?? '',
              'accessToken': entry.value['access_token'] ?? '',
              'refreshToken': entry.value['refresh_token'] ?? '',
              'tokenExpiresAt': entry.value['token_expires_at'] ?? 0,
              'refreshTokenExpiresAt': entry.value['refresh_token_expires_at'] ?? 0,
            }).toList();
        
        print('Loaded ${allAccounts.length} TikTok accounts from Firebase');
        
        setState(() {
          // Separate active and inactive accounts
          _accounts = allAccounts.where((account) => account['status'] == 'active').toList();
          _inactiveAccounts = allAccounts.where((account) => account['status'] == 'inactive').toList();
          _isLoading = false;
        });
        
        print('Active accounts: ${_accounts.length}, Inactive accounts: ${_inactiveAccounts.length}');
      } else {
        print('No TikTok accounts found for user');
        setState(() {
          _accounts = [];
          _inactiveAccounts = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading accounts: $e');
      print('Stack trace: ${StackTrace.current}');
      setState(() => _isLoading = false);
      // SnackBar rimossa come richiesto
    }
  }

  Future<void> _fetchTikTokUserProfile(
    String accessToken,
    String openId,
    String? refreshToken,
    int? expiresIn,
    int? refreshExpiresIn,
    [String? scope, Map<String, dynamic>? fieldsInfo]
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');
      
      // Debug the scope to see what we actually have access to
      print('TikTok token scope: "$scope"');
      
      // Usiamo campi per info base ma SENZA username che causa 401
      String userInfoFields = 'open_id,display_name,avatar_url';
      
      // Usiamo campi specifici per le statistiche, seguendo la documentazione TikTok
      String userStatsFields = 'follower_count,following_count';
      
      // Usa i campi forniti da TikTok se disponibili, ma filtra username
      if (fieldsInfo != null) {
        if (fieldsInfo['user_info_fields'] != null) {
          // Rimuovi 'username' dai campi forniti
          String providedFields = fieldsInfo['user_info_fields'].toString();
          List<String> fieldsList = providedFields.split(',');
          fieldsList.removeWhere((field) => field.trim() == 'username');
          userInfoFields = fieldsList.join(',');
          
          print('Using TikTok-provided user_info_fields (without username): $userInfoFields');
        }
        
        if (fieldsInfo['user_stats_fields'] != null) {
          userStatsFields = fieldsInfo['user_stats_fields'].toString();
          print('Using TikTok-provided user_stats_fields: $userStatsFields');
        }
      }
      
      // Print debug info about scopes and fields
      print('Using fields for user info: $userInfoFields');
      print('Using fields for user stats: $userStatsFields');
      
      // Verifichiamo gli scope disponibili
      bool hasUserInfoScope = scope != null && scope.contains('user.info.basic');
      bool hasUserStatsScope = scope != null && scope.contains('user.info.stats');
      
      // Fetch user info - this must be done even if API fails to ensure we save token data
      Map<String, dynamic> userData = {};
      Map<String, dynamic> statsData = {};
      
      try {
        // Only attempt to fetch if we have the proper scope
        if (hasUserInfoScope) {
          final userInfoData = await _fetchTikTokUserInfo(accessToken, userInfoFields);
          if (userInfoData.containsKey('data') && userInfoData['data'] != null && 
              userInfoData['data'] is Map && userInfoData['data'].containsKey('user')) {
            userData = Map<String, dynamic>.from(userInfoData['data']['user'] as Map);
          } else if (userInfoData.containsKey('error')) {
            print('TikTok API error fetching user info: ${userInfoData['error']}');
          }
        } else {
          print('User.info.basic scope not granted, skipping user info fetch');
        }
      } catch (e) {
        print('Error fetching user info: $e');
      }
      
      // Proviamo a recuperare le statistiche se abbiamo lo scope
      try {
        // Only attempt to fetch stats if we have the proper scope
        if (hasUserStatsScope) {
          final userStatsData = await _fetchTikTokUserStats(accessToken, userStatsFields);
          
          // Cerca i dati delle statistiche in più posizioni possibili nella risposta
          if (userStatsData.containsKey('data')) {
            final data = userStatsData['data'];
            
            // Prima possibilità: stats è direttamente in data
            if (data is Map && data.containsKey('stats')) {
              statsData = Map<String, dynamic>.from(data['stats'] as Map);
              print('Found stats in data.stats path');
            } 
            // Seconda possibilità: stats è dentro data.user
            else if (data is Map && data.containsKey('user')) {
              final user = data['user'];
              if (user is Map) {
                // Controlla se ci sono campi di statistiche direttamente nell'oggetto utente
                final possibleStatFields = ['follower_count', 'following_count', 'likes_count', 'video_count'];
                bool foundStats = false;
                
                for (var field in possibleStatFields) {
                  if (user.containsKey(field)) {
                    // Se troviamo almeno un campo di statistiche, aggiungiamo tutti quelli trovati
                    foundStats = true;
                    statsData[field] = user[field];
                  }
                }
                
                if (foundStats) {
                  print('Found stats directly in user object');
                }
              }
            }
          } else if (userStatsData.containsKey('error')) {
            print('TikTok API error fetching user stats: ${userStatsData['error']}');
          }
          
          // Se non abbiamo trovato dati delle statistiche, stampa un messaggio di debug
          if (statsData.isEmpty) {
            print('Could not find stats data in the response structure');
            print('Response structure: ${userStatsData.keys.toList()}');
          }
        } else {
          print('User.info.stats scope not granted, skipping user stats fetch');
        }
      } catch (e) {
        print('Error fetching user stats: $e');
      }
      
      print('Final user data: $userData');
      print('Final stats data: $statsData');
      
      // Gestisci l'immagine profilo TikTok
      String profileImageUrl = '';
      String profileImageUrl100 = '';
      String profileImageLargeUrl = '';
      
      final originalAvatarUrl = userData['avatar_url'] ?? '';
      final originalAvatarUrl100 = userData['avatar_url_100'] ?? '';
      final originalAvatarLargeUrl = userData['avatar_large_url'] ?? '';
      
      // Scarica e carica l'immagine profilo principale su Cloudflare R2 se disponibile
      if (originalAvatarUrl.isNotEmpty) {
        try {
          print('Downloading and uploading TikTok profile image for user: $openId');
          final cloudflareProfileImageUrl = await _downloadAndUploadProfileImage(originalAvatarUrl, openId);
          if (cloudflareProfileImageUrl != null) {
            profileImageUrl = cloudflareProfileImageUrl;
            print('TikTok profile image saved to Cloudflare R2: $profileImageUrl');
          } else {
            // Fallback all'URL originale se il download/upload fallisce
            profileImageUrl = originalAvatarUrl;
            print('Failed to upload to Cloudflare R2, using original URL: $profileImageUrl');
          }
        } catch (e) {
          print('Error processing TikTok profile image: $e');
          // Fallback all'URL originale in caso di errore
          profileImageUrl = originalAvatarUrl;
        }
      }
      
      // Per le altre dimensioni dell'immagine, usa gli URL originali per ora
      // (potremmo implementare il download anche per queste in futuro)
      profileImageUrl100 = originalAvatarUrl100;
      profileImageLargeUrl = originalAvatarLargeUrl;
      
      // Prepare account data with all available profile information
      // We must save the token information even if the user info fetch fails
      final accountData = {
        // Basic account data - use defaults if API fails
        'name': userData['display_name'] ?? 'TikTok User',
        'display_name': userData['display_name'] ?? 'TikTok User',
        'username': userData['username'] ?? '',
        'bio': userData['bio_description'] ?? '',
        'is_verified': userData['is_verified'] ?? false,
        'profile_deep_link': userData['profile_deep_link'] ?? '',
        
        // Always include these timestamp fields
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'last_sync': DateTime.now().millisecondsSinceEpoch,
        'status': 'active',
        
        // Critical token information - always save these
        'access_token': accessToken,
        'open_id': openId,
        'union_id': userData['union_id'] ?? '',
        
        // Store profile image URLs (main image from Cloudflare R2, others from original)
        'profile_image_url': profileImageUrl,
        'profile_image_url_100': profileImageUrl100,
        'profile_image_large_url': profileImageLargeUrl,
        
        // Store follower and following counts if available, altrimenti usa default
        'followers_count': statsData['follower_count'] ?? 0,
        'following_count': statsData['following_count'] ?? 0,
        'video_count': statsData['video_count'] ?? 0,
        'likes_count': statsData['likes_count'] ?? 0,
        'scopes': scope ?? '',
      };
      
      // Add refresh token and expiration data if available
      if (refreshToken != null) {
        accountData['refresh_token'] = refreshToken;
      }
      
      if (expiresIn != null) {
        accountData['token_expires_at'] = DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch;
      }
      
      if (refreshExpiresIn != null) {
        accountData['refresh_token_expires_at'] = DateTime.now().add(Duration(seconds: refreshExpiresIn)).millisecondsSinceEpoch;
      }
      
      print('Saving TikTok account data to Firebase...');
      
      // Save TikTok account to Firebase - even with just token info if API calls fail
      await _database.child('users/${user.uid}/tiktok/$openId').set(accountData);
      print('Successfully saved TikTok account to Firebase');
      
    } catch (e) {
      print('Error in _fetchTikTokUserProfile: $e');
      print('Stack trace: ${StackTrace.current}');
      throw e;
    } finally {
      // Clear PKCE values after use
      _codeVerifier = null;
      _codeChallenge = null;
    }
  }
  
  // Helper method to fetch TikTok user info
  Future<Map<String, dynamic>> _fetchTikTokUserInfo(String accessToken, String fields) async {
    try {
      print('Fetching TikTok user info with fields: $fields');
      final userInfoResponse = await http.get(
        Uri.parse('https://open.tiktokapis.com/v2/user/info/?fields=$fields'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );
      
      print('User info response status: ${userInfoResponse.statusCode}');
      
      if (userInfoResponse.statusCode == 200) {
        final responseBody = userInfoResponse.body;
        final Map<String, dynamic> userInfoData = json.decode(responseBody);
        print('User info response: $userInfoData');
        return userInfoData;
      } else {
        print('Error fetching user info: ${userInfoResponse.body}');
        // Try to parse error response
        try {
          return json.decode(userInfoResponse.body);
        } catch (e) {
          return {'error': 'HTTP ${userInfoResponse.statusCode}', 'message': userInfoResponse.body};
        }
      }
    } catch (e) {
      print('Exception fetching user info: $e');
      return {'error': 'Exception', 'message': e.toString()};
    }
  }

  // Helper method to fetch TikTok user stats
  Future<Map<String, dynamic>> _fetchTikTokUserStats(String accessToken, String fields) async {
    try {
      print('Fetching TikTok user stats with fields: $fields');
      
      // Proviamo prima l'approccio standard
      var userStatsResponse = await http.get(
        Uri.parse('https://open.tiktokapis.com/v2/user/stats/?fields=$fields'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );
      
      print('User stats response status: ${userStatsResponse.statusCode}');
      
      // Se riceviamo un 404, proviamo con un approccio alternativo
      if (userStatsResponse.statusCode == 404) {
        print('⚠️ Stats endpoint returned 404. Trying alternative approach...');
        
        // Metodo alternativo - proviamo a chiamare l'endpoint /user/info/ con i campi statistici
        // Alcuni sviluppatori riferiscono che potrebbero essere disponibili nello stesso endpoint delle info base
        userStatsResponse = await http.get(
          Uri.parse('https://open.tiktokapis.com/v2/user/info/?fields=$fields'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        );
        
        print('Alternative stats approach response status: ${userStatsResponse.statusCode}');
        
        // Se anche il secondo tentativo fallisce, proviamo un terzo approccio combinando info e stats
        if (userStatsResponse.statusCode != 200) {
          print('⚠️ Second approach failed. Trying a combined approach with all fields...');
          
          // Combiniamo campi base e statistici - SENZA username che causa errore 401
          final combinedFields = 'open_id,display_name,avatar_url,follower_count,following_count,likes_count,video_count';
          
          userStatsResponse = await http.get(
            Uri.parse('https://open.tiktokapis.com/v2/user/info/?fields=$combinedFields'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          );
          
          print('Combined fields approach response status: ${userStatsResponse.statusCode}');
        }
      }
      
      if (userStatsResponse.statusCode == 200) {
        final responseBody = userStatsResponse.body;
        final Map<String, dynamic> userStatsData = json.decode(responseBody);
        print('User stats response: $userStatsData');
        return userStatsData;
      } else {
        print('Error fetching user stats: ${userStatsResponse.body}');
        
        // Try to parse error response
        try {
          return json.decode(userStatsResponse.body);
        } catch (e) {
          return {'error': 'HTTP ${userStatsResponse.statusCode}', 'message': userStatsResponse.body};
        }
      }
    } catch (e) {
      print('Exception fetching user stats: $e');
      return {'error': 'Exception', 'message': e.toString()};
    }
  }

  // Nuovo metodo per pulire i dati di connessione specifici
  void _clearConnectionData() {
    _codeVerifier = null;
    _codeChallenge = null;
    print('Cleared previous connection data');
  }

  // Initialize tutorial video controller
  Future<void> _initializeTutorialVideo() async {
    try {
      print('Initializing TikTok tutorial video...');
      _tutorialVideoController = VideoPlayerController.asset('assets/animations/tutorial/tiktok.mp4');
      await _tutorialVideoController!.initialize();
      _tutorialVideoController!.setLooping(true);
      _tutorialVideoController!.setVolume(0.0); // Mute per il tutorial
      
      print('TikTok tutorial video initialized successfully');
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
                // Video fullscreen con design copiato da video_quick_view_page.dart
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.90, // Ridotto da 0.95 a 0.90 (circa 1cm in meno)
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
                
                // Overlay per il tap play/pause - identico a Instagram
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.90,
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
      );
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
          height: MediaQuery.of(context).size.height * 0.70, // Ridotta da 0.75 a 0.70 per evitare overflow
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
                          width: 160, // Ridotto da 200 a 160 per evitare overflow
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF00F2EA).withOpacity(0.3),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00F2EA).withOpacity(0.1),
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
                                        'TikTok Tutorial',
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
                      'To upload videos on TikTok, you need a Business account',
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
                      'It takes just 30 seconds to transform your TikTok account into a Business account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12, // Font più piccolo per il messaggio secondario
                        color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                        height: 1.3,
                      ),
                    ),
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
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF00F2EA), // TikTok turchese
                        Color(0xFFFF0050), // TikTok rosa
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: ElevatedButton(
                    onPressed: () async {
                      _pauseTutorialVideo(); // Pausa il video quando si chiude
                      
                      // Apri TikTok app o sito web
                      final tiktokUrl = Uri.parse('https://www.tiktok.com');
                      if (await canLaunchUrl(tiktokUrl)) {
                        await launchUrl(
                          tiktokUrl,
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
                          'Open TikTok',
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

  // Add debug options method
  void _showDebugOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'TikTok Connection Debug',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.open_in_browser),
              title: Text('Open TikTok Auth URL in browser'),
              subtitle: Text('Try authenticating directly in the system browser'),
              onTap: () async {
                Navigator.pop(context);
                
                final redirectUri = 'https://viralystsupport.info/';
                final authUrl = Uri.https('www.tiktok.com', '/v2/auth/authorize/', {
                  'client_key': _clientKey,
                  'scope': _tiktokScopes.join(','),
                  'response_type': 'code',
                  'redirect_uri': redirectUri,
                  'state': DateTime.now().millisecondsSinceEpoch.toString(),
                  'prompt': 'consent',
                  'disable_auto_auth': '1', // Force display of authorization page
                });
                
                if (await canLaunchUrl(authUrl)) {
                  await launchUrl(
                    authUrl,
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.copy),
              title: Text('Copy Auth URL to clipboard'),
              subtitle: Text('Copy URL to manually paste in a browser'),
              onTap: () async {
                final redirectUri = 'https://viralystsupport.info/';
                
                // Generate PKCE values
                final codeVerifier = _generateRandomString(128);
                final codeChallenge = _generateCodeChallenge(codeVerifier);
                
                // Store PKCE values for later use
                _codeVerifier = codeVerifier;
                _codeChallenge = codeChallenge;
                
                final authUrl = Uri.https('www.tiktok.com', '/v2/auth/authorize/', {
                  'client_key': _clientKey,
                  'scope': _tiktokScopes.join(','),
                  'response_type': 'code',
                  'redirect_uri': redirectUri,
                  'code_challenge': codeChallenge,
                  'code_challenge_method': 'S256',
                  'state': DateTime.now().millisecondsSinceEpoch.toString(),
                  'prompt': 'consent',
                  'disable_auto_auth': '1', // Force display of authorization page
                });
                
                // Copy URL to clipboard
                await Clipboard.setData(ClipboardData(text: authUrl.toString()));
                
                // Show a message and close the bottom sheet
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Auth URL copied to clipboard. Paste it in a browser to continue.')),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Check TikTok App Setup'),
              subtitle: Text('Verify your TikTok developer settings'),
              onTap: () {
                Navigator.pop(context);
                _showTikTokSetupInfo();
              },
            ),
            ListTile(
              leading: Icon(Icons.switch_access_shortcut),
              title: Text('Try alternative auth approach'),
              subtitle: Text('Use a different URL format that might work better'),
              onTap: () async {
                Navigator.pop(context);
                
                // Generate PKCE values
                _codeVerifier = _generateRandomString(128);
                _codeChallenge = _generateCodeChallenge(_codeVerifier!);
                
                // Use www.tiktok.com instead of open.tiktokapis.com
                final altAuthUrl = Uri.parse(
                  'https://www.tiktok.com/auth/authorize/?client_key=${_clientKey}'
                  '&scope=${Uri.encodeComponent(_tiktokScopes.join(","))}'
                  '&response_type=code'
                  '&redirect_uri=${Uri.encodeComponent("https://viralystsupport.info/")}'
                  '&code_challenge=${Uri.encodeComponent(_codeChallenge!)}'
                  '&code_challenge_method=S256'
                  '&state=${DateTime.now().millisecondsSinceEpoch}'
                  '&disable_auto_auth=1'
                );
                
                print('Trying alternative TikTok auth URL: $altAuthUrl');
                
                if (await canLaunchUrl(altAuthUrl)) {
                  await launchUrl(
                    altAuthUrl,
                    mode: LaunchMode.externalApplication,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not launch alternative auth URL')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
  
  // Method to show TikTok setup information
  void _showTikTokSetupInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('TikTok App Setup Check'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Verify these settings in your TikTok Developer account:'),
              SizedBox(height: 10),
              Text('• Client Key: $_clientKey', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
              Text('• Redirect URI: https://viralystsupport.info/', 
                style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
              Text('• Make sure OAuth is enabled for your app'),
              Text('• Verify the scopes are approved:'),
              ..._tiktokScopes.map((scope) => 
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text('- $scope', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
                )
              ),
              SizedBox(height: 10),
              Text('If you continue to have issues, check if:'),
              Text('• Your app is in development or live mode'),
              Text('• Your test account is added as a tester'),
              Text('• You have the correct Android/iOS settings'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  // Override didUpdateWidget to clean data when page is updated
  @override
  void didUpdateWidget(TikTokPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pulisci i dati di autenticazione quando la pagina viene aggiornata
    _clearAllLocalAuthData();
    _loadAccounts();
  }

  Future<void> _reactivateAccount(String accountId) async {
    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _database.child('users/${user.uid}/tiktok/$accountId').update({
        'status': 'active',
      });

      await _loadAccounts();

      if (mounted) {
        // SnackBar rimossa come richiesto
      }
    } catch (e) {
      print('Error reactivating account: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reactivating account: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _hasShownTiktokInfo = false;
}
