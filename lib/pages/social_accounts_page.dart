import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';

// Importiamo il routeObserver dal main.dart
import '../main.dart';

class SocialAccountsPage extends StatefulWidget {
  const SocialAccountsPage({super.key});

  @override
  State<SocialAccountsPage> createState() => SocialAccountsPageState();
}

class SocialAccountsPageState extends State<SocialAccountsPage> with WidgetsBindingObserver, RouteAware {
  // Altezza riservata per la top bar flottante (ridotta per eliminare lo spazio extra)
  static const double _headerReservedSpace = 80.0;
  int _connectedAccountsCount = 0;
  bool _isLoading = true;
  // Flag per evitare carichi ripetuti
  bool _dataLoaded = false;
  bool _isInitialLoad = true;
  // Stato per mostrare il popup TikTok info
  bool _showTiktokInfo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Carica i dati appena la pagina viene creata
    loadConnectedAccountsCount();
  }
  
  @override
  void didUpdateWidget(covariant SocialAccountsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeShowTiktokDialog();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Registra questo widget con routeObserver
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
    _maybeShowTiktokDialog();
  }
  
  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data when app is resumed
      loadConnectedAccountsCount();
    }
  }

  // Chiamato quando questa route diventa visibile
  @override
  void didPushNext() {
    // Questa pagina non è più visibile (un'altra pagina è stata spinta sopra)
    _dataLoaded = false;
  }
  
  // Chiamato quando questa route diventa visibile di nuovo dopo un pop di un'altra route
  @override
  void didPopNext() {
    // La pagina è tornata visibile dopo che un'altra pagina è stata rimossa
    if (!_dataLoaded) {
      loadConnectedAccountsCount();
    }
  }

  Future<void> loadConnectedAccountsCount() async {
    // Mostra il loading indicator solo al primo caricamento
    if (_isInitialLoad && !_isLoading) {
      setState(() {
        _isLoading = true;
      });
    }
    
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
          _dataLoaded = true;
        });
        return;
      }

      // Count for all possible paths where accounts could be stored
      int totalCount = 0;
      
      // Check in users/{uid}/tiktok path
      final tiktokRef = FirebaseDatabase.instance.ref()
          .child('users')
          .child(currentUser.uid)
          .child('tiktok');
          
      final tiktokSnapshot = await tiktokRef.get();
      if (tiktokSnapshot.exists && tiktokSnapshot.value is Map) {
        final tiktokData = tiktokSnapshot.value as Map<dynamic, dynamic>;
        tiktokData.forEach((id, accountData) {
          if (accountData is Map && accountData['status'] != 'inactive') {
            totalCount++;
          }
        });
      }
      
      // Check in users/{uid} direct path
      final userDirectRef = FirebaseDatabase.instance.ref()
          .child('users')
          .child(currentUser.uid);
      
      final directSnapshot = await userDirectRef.get();
      if (directSnapshot.exists && directSnapshot.value is Map) {
        final userData = directSnapshot.value as Map<dynamic, dynamic>;
        
        // Count platforms directly under the user node
        for (final platform in ['facebook', 'instagram', 'twitter', 'youtube', 'threads']) {
          if (userData.containsKey(platform) && userData[platform] is Map) {
            final accounts = userData[platform] as Map<dynamic, dynamic>;
            accounts.forEach((id, accountData) {
              if (accountData is Map && (accountData['status'] == 'active' || accountData['status'] == null)) {
                totalCount++;
              }
            });
          }
        }
      }
      
      // Check in users/users/{uid}/social_accounts path
      final nestedUserRef = FirebaseDatabase.instance.ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts');
      
      final nestedSnapshot = await nestedUserRef.get();
      if (nestedSnapshot.exists && nestedSnapshot.value is Map) {
        final data = nestedSnapshot.value as Map<dynamic, dynamic>;
        
        data.forEach((platform, accounts) {
          if (accounts is Map) {
            accounts.forEach((id, account) {
              if (account is Map && account['status'] != 'inactive') {
                totalCount++;
              }
            });
          }
        });
      }
      
      // Check platform-specific nodes in users/users/{uid}
      final userRef = FirebaseDatabase.instance.ref()
          .child('users')
          .child('users')
          .child(currentUser.uid);
          
      final userSnapshot = await userRef.get();
      if (userSnapshot.exists && userSnapshot.value is Map) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        
        // Check platform-specific nodes
        for (final platform in ['facebook', 'instagram', 'twitter', 'youtube', 'threads']) {
          if (userData.containsKey(platform) && userData[platform] is Map) {
            final accounts = userData[platform] as Map<dynamic, dynamic>;
            accounts.forEach((id, accountData) {
              if (accountData is Map && accountData['status'] != 'inactive') {
                totalCount++;
              }
            });
          }
        }
      }
      
      // Verifica ulteriormente il percorso specifico per TikTok
      final tiktokUserRef = FirebaseDatabase.instance.ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('tiktok');
          
      final tiktokUserSnapshot = await tiktokUserRef.get();
      if (tiktokUserSnapshot.exists && tiktokUserSnapshot.value is Map) {
        final tiktokUserData = tiktokUserSnapshot.value as Map<dynamic, dynamic>;
        tiktokUserData.forEach((id, accountData) {
          if (accountData is Map && accountData['status'] != 'inactive') {
            totalCount++;
          }
        });
      }
      
      print('Total connected accounts found: $totalCount');
      
      // Update state with total count
      if (mounted) {
        setState(() {
          _connectedAccountsCount = totalCount;
          _isLoading = false;
          _dataLoaded = true;
          _isInitialLoad = false;
        });
      }
    } catch (e) {
      print('Error loading connected accounts: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _dataLoaded = true;
          _isInitialLoad = false;
        });
      }
    }
  }

  void _maybeShowTiktokDialog() {
    if (_showTiktokInfo) {
      // Mostra il dialog solo se non è già visibile
      _showTiktokInfo = false;
      Future.microtask(() => showDialog(
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
                  'TikTok integration is currently in testing. For now, videos will NOT be published on TikTok.\n\nThis is only temporary: publishing to TikTok will be available soon.',
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
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
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
        body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              // Riduciamo lo spazio superiore per avvicinare la card "Connect Your Platforms" alla top bar
              padding: EdgeInsets.fromLTRB(16, _headerReservedSpace, 16, 84),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Introduction section - updated with glass opaque effect and gradient
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
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
                      // Gradiente lineare a 135 gradi
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF667eea), // Colore iniziale: blu violaceo
                          Color(0xFF764ba2), // Colore finale: viola
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.connect_without_contact,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'Connect Your Platforms',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Link your social media accounts to start scheduling and managing your content across multiple platforms.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.9),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Connected accounts stat card
                  Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 20),
                    child: _buildConnectedAccountsCard(
                      context,
                      _isLoading ? '...' : _connectedAccountsCount.toString(),
                    ),
                  ),
                  
                  // Social accounts section - Updated header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 20),
                    child: Center(
                      child: ShaderMask(
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
                          'Available Platforms',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 20,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  // Available platforms
                  _buildSocialAccountCard(
                    context,
                    'YouTube',
                    'Connect YouTube channel',
                    'assets/loghi/logo_yt.png',
                    const Color(0xFFFF0000),
                    () => Navigator.pushNamed(context, '/youtube'),
                  ),
                  _buildSocialAccountCard(
                    context,
                    'Instagram',
                    'Connect Instagram account',
                    'assets/loghi/logo_insta.png',
                    const Color(0xFFE1306C),
                    () => Navigator.pushNamed(context, '/instagram'),
                  ),
                  _buildSocialAccountCard(
                    context,
                    'Facebook',
                    'Connect Facebook page',
                    'assets/loghi/logo_facebook.png',
                    const Color(0xFF1877F2),
                    () => Navigator.pushNamed(context, '/facebook'),
                  ),
                  _buildSocialAccountCard(
                    context,
                    'Threads',
                    'Connect Threads account',
                    'assets/loghi/threads_logo.png',
                    const Color(0xFF000000),
                    () => Navigator.pushNamed(context, '/threads'),
                  ),
                  // Sezione Coming Soon
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                    child: Center(
                      child: ShaderMask(
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
                          'Coming Soon',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 20,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  _buildSocialAccountCard(
                    context,
                    'TikTok',
                    'Integration coming soon',
                    'assets/loghi/logo_tiktok.png',
                    const Color(0xFF000000),
                    () => Navigator.pushNamed(context, '/tiktok'),
                  ),
                  _buildSocialAccountCard(
                    context,
                    'Twitter',
                    'Integration coming soon',
                    'assets/loghi/logo_twitter.png',
                    const Color(0xFF1DA1F2),
                    () => Navigator.pushNamed(context, '/twitter'),
                  ),
                  const SizedBox(height: 20), // Reduced space at bottom
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  }

  // Enhanced connected accounts card with glass effect matching AI Powered card
  Widget _buildConnectedAccountsCard(
    BuildContext context,
    String count,
  ) {
    final bool isShowingInitialLoading = _isInitialLoad && _isLoading;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      width: double.infinity,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                  size: 28,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'Connected Accounts',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        isShowingInitialLoading 
                          ? 'Loading your accounts...'
                          : _connectedAccountsCount > 0 
                            ? 'Your accounts are linked to Fluzar'
                            : 'No accounts linked yet',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea), // Colore iniziale: blu violaceo
                      Color(0xFF764ba2), // Colore finale: viola
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  isShowingInitialLoading ? '...' : count,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Updated social card widget with glass opaque effect matching AI Powered card
  Widget _buildSocialAccountCard(
    BuildContext context,
    String title,
    String subtitle,
    String logoAsset,
    Color brandColor,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: (title.toLowerCase() == 'twitter' || title.toLowerCase() == 'tiktok') ? null : () async {
                final result = await Navigator.pushNamed(context, '/$title'.toLowerCase());
                if (result == true) {
                  loadConnectedAccountsCount();
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: brandColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Image.asset(
                        logoAsset,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (title.toLowerCase() != 'twitter' && title.toLowerCase() != 'tiktok')
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: ShaderMask(
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
                          child: Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Public method for external access to refresh accounts count
  void refreshAccountsCount() {
    loadConnectedAccountsCount();
  }

  Widget _buildFloatingHeader(ThemeData theme) {
    return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // Nessuna decorazione: niente bordo arrotondato, niente ombra, niente sfondo "card"
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                  color: theme.brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                      size: 22,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return LinearGradient(
                        colors: const [
                          Color(0xFF667eea),
                          Color(0xFF764ba2),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180),
                      ).createShader(bounds);
                    },
                child: const Text(
                      'Social Accounts',
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                Icon(
                  Icons.layers_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                    const SizedBox(width: 6),
                    Text(
                      '${_connectedAccountsCount.clamp(0, 999)} linked',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
      ),
    );
  }
} 