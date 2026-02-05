import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter
import 'profile_page.dart';
import 'about_page.dart';
import 'refeeral_code_page.dart';
import 'credits_page.dart';
import '../providers/theme_provider.dart';
import '../providers/tutorial_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'help/change_password_page.dart';
import 'help/troubleshooting_page.dart';
import 'help/contact_support_page.dart';
import 'help/uploading_videos_page.dart';
import 'help/scheduling_videos_page.dart';
import '../services/stripe_service.dart';
import 'onboarding_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart'; // <--- AGGIUNTO
import 'package:google_sign_in/google_sign_in.dart';
import 'upgrade_premium_ios_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // bool _notificationsEnabled = true; // RIMOSSO
  String _selectedDateFormat = 'DD/MM/YYYY';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final GlobalKey _settingsTutorialKey = GlobalKey(debugLabel: 'settings_tutorial');
  bool _isPremium = false; // <--- AGGIUNTO per tracciare lo stato premium

  final List<String> _dateFormats = ['DD/MM/YYYY', 'MM/DD/YYYY', 'YYYY-MM-DD'];

  // Lingua per analisi IA
  String _selectedLanguage = 'it'; // default Italiano
  final Map<String, String> _languages = const {
    'sq': 'Shqip',
    'ar': 'العربية',
    'bn': 'বাংলা',
    'bs': 'Bosanski',
    'bg': 'Български',
    'ca': 'Català',
    'zh': '中文 (简体)',
    'hr': 'Hrvatski',
    'da': 'Dansk',
    'nl': 'Nederlands',
    'en': 'English',
    'et': 'Eesti',
    'fi': 'Suomi',
    'fr': 'Français',
    'gl': 'Galego',
    'de': 'Deutsch',
    'el': 'Ελληνικά',
    'he': 'עברית',
    'hi': 'हिन्दी',
    'hu': 'Magyar',
    'id': 'Bahasa Indonesia',
    'it': 'Italiano',
    'ja': '日本語',
    'ko': '한국어',
    'lv': 'Latviešu',
    'lt': 'Lietuvių',
    'ms': 'Bahasa Melayu',
    'mt': 'Malti',
    'mk': 'Македонски',
    'mr': 'मराठी',
    'no': 'Norsk',
    'pl': 'Polski',
    'pt': 'Português',
    'pa': 'ਪੰਜਾਬੀ',
    'fa': 'فارسی',
    'fil': 'Filipino',
    'ro': 'Română',
    'ru': 'Русский',
    'sr': 'Српски',
    'sk': 'Slovenčina',
    'sl': 'Slovenščina',
    'es': 'Español',
    'sv': 'Svenska',
    'sw': 'Kiswahili',
    'ta': 'தமிழ்',
    'th': 'ไทย',
    'tr': 'Türkçe',
    'tk': 'Türkmen',
    'uk': 'Українська',
    'ur': 'اردو',
    'eu': 'Euskara',
    'vi': 'Tiếng Việt',
    'te': 'తెలుగు',
    'ka': 'ქართული',
  };
  // Mappa codice -> nome lingua in inglese
  final Map<String, String> _codeToEnglish = const {
    'sq': 'albanian',
    'ar': 'arabic',
    'bn': 'bengali',
    'bs': 'bosnian',
    'bg': 'bulgarian',
    'ca': 'catalan',
    'zh': 'chinese',
    'hr': 'croatian',
    'da': 'danish',
    'nl': 'dutch',
    'en': 'english',
    'et': 'estonian',
    'fi': 'finnish',
    'fr': 'french',
    'gl': 'galician',
    'de': 'german',
    'el': 'greek',
    'he': 'hebrew',
    'hi': 'hindi',
    'hu': 'hungarian',
    'id': 'indonesian',
    'it': 'italian',
    'ja': 'japanese',
    'ko': 'korean',
    'lv': 'latvian',
    'lt': 'lithuanian',
    'ms': 'malay',
    'mt': 'maltese',
    'mk': 'macedonian',
    'mr': 'marathi',
    'no': 'norwegian',
    'pl': 'polish',
    'pt': 'portuguese',
    'pa': 'punjabi',
    'fa': 'persian',
    'fil': 'filipino',
    'ro': 'romanian',
    'ru': 'russian',
    'sr': 'serbian',
    'sk': 'slovak',
    'sl': 'slovenian',
    'es': 'spanish',
    'sv': 'swedish',
    'sw': 'swahili',
    'ta': 'tamil',
    'th': 'thai',
    'tr': 'turkish',
    'tk': 'turkmen',
    'uk': 'ukrainian',
    'ur': 'urdu',
    'eu': 'basque',
    'vi': 'vietnamese',
    'te': 'telugu',
    'ka': 'georgian',
  };
  // Mappa nome inglese -> codice
  final Map<String, String> _englishToCode = const {
    'albanian': 'sq',
    'arabic': 'ar',
    'bengali': 'bn',
    'bosnian': 'bs',
    'bulgarian': 'bg',
    'catalan': 'ca',
    'chinese': 'zh',
    'croatian': 'hr',
    'danish': 'da',
    'dutch': 'nl',
    'english': 'en',
    'estonian': 'et',
    'finnish': 'fi',
    'french': 'fr',
    'galician': 'gl',
    'german': 'de',
    'greek': 'el',
    'hebrew': 'he',
    'hindi': 'hi',
    'hungarian': 'hu',
    'indonesian': 'id',
    'italian': 'it',
    'japanese': 'ja',
    'korean': 'ko',
    'latvian': 'lv',
    'lithuanian': 'lt',
    'malay': 'ms',
    'maltese': 'mt',
    'macedonian': 'mk',
    'marathi': 'mr',
    'norwegian': 'no',
    'polish': 'pl',
    'portuguese': 'pt',
    'punjabi': 'pa',
    'persian': 'fa',
    'filipino': 'fil',
    'romanian': 'ro',
    'russian': 'ru',
    'serbian': 'sr',
    'slovak': 'sk',
    'slovenian': 'sl',
    'spanish': 'es',
    'swedish': 'sv',
    'swahili': 'sw',
    'tamil': 'ta',
    'thai': 'th',
    'turkish': 'tr',
    'turkmen': 'tk',
    'ukrainian': 'uk',
    'urdu': 'ur',
    'basque': 'eu',
    'vietnamese': 'vi',
    'telugu': 'te',
    'georgian': 'ka',
  };

  User? _currentUser; // <--- AGGIUNTO
  bool get _isJacopo => _currentUser?.email == 'jacopoberto19@gmail.com'; // <--- AGGIUNTO
  bool get _isAuthorizedUser => _currentUser?.email == 'jacopoberto19@gmail.com' || _currentUser?.email == 'giuseppemaria162@gmail.com'; // <--- AGGIUNTO per Profile
  
  // Variabili per le impostazioni di privacy
  bool _isProfilePublic = true;
  bool _showViralystScore = true;
  bool _showVideoCount = true;
  bool _showLikeCount = true;
  bool _showCommentCount = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUser = FirebaseAuth.instance.currentUser; // <-- subito
    _checkPremiumStatus(); // <--- AGGIUNTO per verificare lo stato premium
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
    _animationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final tutorialProvider = Provider.of<TutorialProvider>(context, listen: false);
        tutorialProvider.setTargetKey(4, _settingsTutorialKey);
        
        // Initialize dark mode from provider
        final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
        
        // Sincronizza automaticamente il tema con quello del dispositivo
        final systemBrightness = MediaQuery.of(context).platformBrightness;
        _syncThemeWithSystem(brightness: systemBrightness);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadLanguagePreference();
    _loadPrivacySettings();
  }

  Future<void> _loadLanguagePreference() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final database = FirebaseDatabase.instance.ref();
      final userRef = database.child('users').child('users').child(user.uid);
      final snapshot = await userRef.child('language_analysis').get();
      if (snapshot.exists && snapshot.value is String) {
        final langEnglish = (snapshot.value as String).toLowerCase();
        if (_englishToCode.containsKey(langEnglish)) {
          setState(() {
            _selectedLanguage = _englishToCode[langEnglish]!;
          });
        } else {
          // Se il valore non è valido, default a inglese
          setState(() {
            _selectedLanguage = 'en';
          });
        }
      } else {
        // Se il campo non esiste, default a inglese
        setState(() {
          _selectedLanguage = 'en';
        });
      }
    }
  }

  Future<void> _saveLanguagePreference(String lang) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final database = FirebaseDatabase.instance.ref();
      final userRef = database.child('users').child('users').child(user.uid);
      final langEnglish = _codeToEnglish[lang] ?? lang;
      await userRef.child('language_analysis').set(langEnglish);
    }
  }

  // Metodo helper per conversione sicura da dynamic a bool
  bool _safeBoolConversion(dynamic value, bool defaultValue) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    if (value is int) {
      return value != 0;
    }
    return defaultValue;
  }

  Future<void> _loadPrivacySettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final database = FirebaseDatabase.instance.ref();
      final userRef = database.child('users').child('users').child(user.uid);
      final profileSnapshot = await userRef.child('profile').get();
      
      if (profileSnapshot.exists && profileSnapshot.value is Map) {
        final profileData = Map<String, dynamic>.from(profileSnapshot.value as Map);
        final newIsProfilePublic = _safeBoolConversion(profileData['isProfilePublic'], true);
        final newShowViralystScore = _safeBoolConversion(profileData['showViralystScore'], true);
        final newShowVideoCount = _safeBoolConversion(profileData['showVideoCount'], true);
        final newShowLikeCount = _safeBoolConversion(profileData['showLikeCount'], true);
        final newShowCommentCount = _safeBoolConversion(profileData['showCommentCount'], true);
        
        print('Caricamento impostazioni privacy: $newIsProfilePublic, $newShowViralystScore, $newShowVideoCount, $newShowLikeCount, $newShowCommentCount');
        
        setState(() {
          _isProfilePublic = newIsProfilePublic;
          _showViralystScore = newShowViralystScore;
          _showVideoCount = newShowVideoCount;
          _showLikeCount = newShowLikeCount;
          _showCommentCount = newShowCommentCount;
        });
      } else {
        print('Nessun profilo trovato, usando valori di default');
        setState(() {
          _isProfilePublic = true;
          _showViralystScore = true;
          _showVideoCount = true;
          _showLikeCount = true;
          _showCommentCount = true;
        });
      }
    }
  }

  // Metodo per verificare se l'utente è premium
  Future<void> _checkPremiumStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final database = FirebaseDatabase.instance.ref();
        final userRef = database.child('users').child('users').child(user.uid);
        final isPremiumSnapshot = await userRef.child('isPremium').get();
        
        if (isPremiumSnapshot.exists) {
          setState(() {
            _isPremium = (isPremiumSnapshot.value as bool?) ?? false;
          });
          print('Stato premium utente: $_isPremium');
        }
      }
    } catch (e) {
      print('Errore nella verifica dello stato premium: $e');
      setState(() {
        _isPremium = false;
      });
    }
  }

  Future<void> _savePrivacySettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final database = FirebaseDatabase.instance.ref();
        final userRef = database.child('users').child('users').child(user.uid);
        
        // Prima carica i dati esistenti del profilo
        final profileSnapshot = await userRef.child('profile').get();
        Map<String, dynamic> profileData = {};
        
        if (profileSnapshot.exists && profileSnapshot.value is Map) {
          profileData = Map<String, dynamic>.from(profileSnapshot.value as Map);
        }
        
        // Aggiorna solo i campi di privacy
        profileData['isProfilePublic'] = _isProfilePublic;
        profileData['showViralystScore'] = _showViralystScore;
        profileData['showVideoCount'] = _showVideoCount;
        profileData['showLikeCount'] = _showLikeCount;
        profileData['showCommentCount'] = _showCommentCount;
        profileData['lastUpdated'] = DateTime.now().millisecondsSinceEpoch;
        
        // Salva tutto il profilo aggiornato
        await userRef.child('profile').set(profileData);
        
        print('Impostazioni privacy salvate con successo: $_isProfilePublic, $_showViralystScore, $_showVideoCount, $_showLikeCount, $_showCommentCount');
      } catch (e) {
        print('Errore nel salvataggio delle impostazioni privacy: $e');
        // Rilancia l'errore per gestirlo nei callback
        throw e;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    super.dispose();
  }

  void _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error signing out: $e')),
      );
    }
  }

  void _shareApp() {
    // Invita ad usare il referral code come in community_page.dart
    () async {
      try {
        final user = FirebaseAuth.instance.currentUser;
        String message =
            'Check out Fluzar, the all-in-one solution for managing your social media content! Download it now: https://fluzar.com';
        String subject = 'Fluzar - Social Media Management Made Easy With AI';
        
        if (user != null) {
          final database = FirebaseDatabase.instance.ref();
          final userRef = database.child('users').child('users').child(user.uid);
          final snapshot = await userRef.get();
          
          String? referralCode;
          if (snapshot.exists && snapshot.value is Map) {
            final userData = snapshot.value as Map<dynamic, dynamic>;
            if (userData.containsKey('referral_code')) {
              referralCode = userData['referral_code'] as String?;
            }
          }
          
          if (referralCode != null && referralCode.isNotEmpty) {
            message =
                'Hey! Join me on Fluzar and get 500 bonus credits! Use my referral code: $referralCode. Download it now: https://fluzar.com';
            subject = 'Join Fluzar - Social Media Management Made Easy With AI';
          }
        }
        
        await Share.share(
          message,
          subject: subject,
        );
      } catch (e) {
        print('Error sharing invite/referral: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error sharing referral code'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }();
  }


  /// Gestisce il reindirizzamento alla pagina di billing di Stripe
  Future<void> _handlePaymentRedirect() async {
    try {
      // Ottieni l'email dell'utente corrente
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception('Utente non autenticato o email non disponibile');
      }

      // Crea una sessione del Customer Portal con pagina di reindirizzamento
      final portalUrl = await StripeService.createCustomerPortalSession(
        customerEmail: user.email!,
        returnUrl: 'https://fluzar.com/deep-redirect.html?to=subscription-cancelled',
      );

      if (portalUrl != null) {
        final Uri url = Uri.parse(portalUrl);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
          throw Exception('Impossibile aprire il Customer Portal');
        }
      } else {
        throw Exception('Impossibile creare la sessione del Customer Portal');
      }
    } catch (e) {
      print('Errore nell\'apertura del Customer Portal: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore nell\'apertura del Customer Portal: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }



  Future<void> _showDateFormatSelectionDialog() async {
    final selectedFormat = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Date Format'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _dateFormats.length,
              itemBuilder: (context, index) {
                return RadioListTile<String>(
                  title: Text(_dateFormats[index]),
                  value: _dateFormats[index],
                  groupValue: _selectedDateFormat,
                  onChanged: (value) {
                    Navigator.of(context).pop(value);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (selectedFormat != null) {
      setState(() {
        _selectedDateFormat = selectedFormat;
      });
    }
  }

  Future<void> _showDeleteAccountDialog() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Warning icon
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_rounded,
                    color: Colors.red,
                    size: 30,
                  ),
                ),
                
                SizedBox(height: 20),
                
                // Title
                Text(
                  'Delete Account',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Warning message
                Text(
                  'This action cannot be undone. All your data will be permanently deleted:',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                SizedBox(height: 16),
                
                // Data list
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Color(0xFF2A2A2A) : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildDataItem(Icons.person_outline, 'Profile information'),
                      _buildDataItem(Icons.settings_outlined, 'App preferences'),
                      _buildDataItem(Icons.history_outlined, 'Activity history'),
                    ],
                  ),
                ),
                
                SizedBox(height: 24),
                
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _deleteAccount();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: Center(
                          child: Text(
                            'Delete Account',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildDataItem(IconData icon, String text) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.red.withOpacity(0.7),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    // Show second confirmation dialog
    final confirmed = await _showFinalConfirmationDialog();
    if (!confirmed) return;
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      // Delete user data from Firebase Database
      final database = FirebaseDatabase.instance.ref();
      final userRef = database.child('users').child('users').child(user.uid);
      
      await userRef.remove();
      
      // Try to delete user from Firebase Auth
      try {
        await user.delete();
      } catch (authError) {
        // If authentication is required, show re-authentication dialog
        if (authError.toString().contains('requires recent authentication')) {
          // Show re-authentication dialog
          final reAuthResult = await _showReAuthenticationDialog();
          if (reAuthResult == true) {
            // Try to delete again after re-authentication
            await user.delete();
          } else {
            // User cancelled re-authentication
            return;
          }
        } else {
          // Re-throw other authentication errors
          throw authError;
        }
      }
      
      // Sign out from Firebase Auth (like logout)
      await FirebaseAuth.instance.signOut();
      
      // Navigate to onboarding page directly (like logout)
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
      
    } catch (e) {
      // Show error message with better error handling
      if (mounted) {
        String errorMessage = 'Error deleting account';
        
        if (e.toString().contains('requires recent authentication')) {
          errorMessage = 'Authentication required. Please try again.';
        } else if (e.toString().contains('network')) {
          errorMessage = 'Network error. Please check your connection and try again.';
        } else if (e.toString().contains('permission')) {
          errorMessage = 'Permission denied. Please try again.';
        } else {
          errorMessage = 'An error occurred while deleting your account. Please try again.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<bool> _showReAuthenticationDialog() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) return false;
    
    // Check if user has email/password provider
    final hasEmailPassword = user.providerData.any((provider) => provider.providerId == 'password');
    
    if (!hasEmailPassword) {
      // For Google/other providers, we need to re-authenticate differently
      try {
        // For Google users, we'll try to re-authenticate with Google
        final googleSignIn = GoogleSignIn();
        final googleUser = await googleSignIn.signIn();
        
        if (googleUser != null) {
          final googleAuth = await googleUser.authentication;
          final credential = GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
          
          await user.reauthenticateWithCredential(credential);
          return true;
        } else {
          return false;
        }
      } catch (e) {
        print('Google re-authentication error: $e');
        return false;
      }
    }
    
    // For email/password users, show password dialog
    final passwordController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Security icon
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.security,
                        color: Colors.orange,
                        size: 30,
                      ),
                    ),
                    
                    SizedBox(height: 20),
                    
                    // Title
                    Text(
                      'Re-authentication Required',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    
                    SizedBox(height: 16),
                    
                    // Message
                    Text(
                      'For security reasons, please enter your password to confirm account deletion.',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    SizedBox(height: 20),
                    
                    // Password field
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: Icon(Icons.lock),
                      ),
                      onSubmitted: (value) async {
                        try {
                          final credential = EmailAuthProvider.credential(
                            email: user.email!,
                            password: value,
                          );
                          await user.reauthenticateWithCredential(credential);
                          Navigator.of(context).pop(true);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Incorrect password. Please try again.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                    ),
                    
                    SizedBox(height: 24),
                    
                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              try {
                                final credential = EmailAuthProvider.credential(
                                  email: user.email!,
                                  password: passwordController.text,
                                );
                                await user.reauthenticateWithCredential(credential);
                                Navigator.of(context).pop(true);
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Incorrect password. Please try again.'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'Confirm',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ) ?? false;
   
   // Dispose the controller after dialog is closed
   passwordController.dispose();
   
   return result;
  }

  Future<bool> _showFinalConfirmationDialog() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Final warning icon
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 30,
                  ),
                ),
                
                SizedBox(height: 20),
                
                // Title
                Text(
                  'Final Confirmation',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Warning message
                Text(
                  'Are you absolutely sure you want to delete your account? This action is irreversible and will permanently remove all your data.',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                SizedBox(height: 24),
                
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: Center(
                          child: Text(
                            'Yes, Delete',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ) ?? false;
  }

  void _showLanguagePicker() {
    final theme = Theme.of(context);
    
    // Controlla se il dispositivo è iOS
    if (Platform.isIOS) {
      // Usa il picker nativo iOS
      showCupertinoModalPopup<void>(
        context: context,
        builder: (BuildContext context) => Container(
          height: 216,
          padding: const EdgeInsets.only(top: 6.0),
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          color: CupertinoColors.systemBackground.resolveFrom(context),
          child: SafeArea(
            top: false,
            child: CupertinoPicker(
              magnification: 1.22,
              squeeze: 1.2,
              useMagnifier: true,
              itemExtent: 32.0,
              scrollController: FixedExtentScrollController(
                initialItem: _languages.keys.toList().indexOf(_selectedLanguage),
              ),
              onSelectedItemChanged: (int selectedItem) async {
                final lang = _languages.keys.elementAt(selectedItem);
                setState(() {
                  _selectedLanguage = lang;
                });
                await _saveLanguagePreference(lang);
              },
              children: List<Widget>.generate(_languages.length, (int index) {
                final lang = _languages.keys.elementAt(index);
                return Center(
                  child: Text(
                    _languages[lang]!,
                    style: const TextStyle(fontSize: 18),
                  ),
                );
              }),
            ),
          ),
        ),
      );
    } else {
      // Usa il picker Material Design per Android e altri
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return Container(
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.only(top: 16, bottom: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
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
                    'Select language AI',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(
                  height: 180,
                  child: CupertinoPicker(
                    backgroundColor: Colors.transparent,
                    itemExtent: 40,
                    scrollController: FixedExtentScrollController(
                      initialItem: _languages.keys.toList().indexOf(_selectedLanguage),
                    ),
                    onSelectedItemChanged: (int index) async {
                      final lang = _languages.keys.elementAt(index);
                      setState(() {
                        _selectedLanguage = lang;
                      });
                      await _saveLanguagePreference(lang);
                    },
                    children: _languages.values.map((label) => Center(child: Text(label, style: TextStyle(fontSize: 18)))).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  void _showPrivacySettings() async {
    // Ricarica le impostazioni prima di aprire la tendina
    await _loadPrivacySettings();
    
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isDismissible: true, // Permette la chiusura toccando fuori
      enableDrag: true, // Permette il drag per chiudere
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  
                  // Header
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: ShaderMask(
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
                          'Privacy Settings',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          _buildStatsVisibilitySectionForModal(theme, setModalState),
                          SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPrivacySection(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
                child: Icon(Icons.security, color: Colors.white, size: 24),
              ),
              SizedBox(width: 12),
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
                  'Privacy Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Gestisci la visibilità del tuo profilo e delle tue statistiche',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsVisibilitySection(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
                child: Icon(Icons.visibility, color: Colors.white, size: 24),
              ),
              SizedBox(width: 12),
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
                  'Profile and Statistics Visibility',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Choose what to show to other users who are not your friends, only your friends can see the complete information.',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          SizedBox(height: 20),
          
          Container(
            decoration: BoxDecoration(
              // Effetto vetro semi-trasparente opaco per il contenitore interno
              color: isDark 
                  ? Colors.white.withOpacity(0.1) 
                  : Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark 
                    ? Colors.white.withOpacity(0.2)
                    : Colors.white.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark 
                      ? Colors.black.withOpacity(0.2)
                      : Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildSwitchTile(
                  icon: Icons.person,
                  title: 'Top and recent videos',
                  value: _isProfilePublic,
                  onChanged: (value) async {
                    setState(() {
                      _isProfilePublic = value;
                    });
                    try {
                      await _savePrivacySettings();
                    } catch (e) {
                      setState(() {
                        _isProfilePublic = !value;
                      });
                    }
                  },
                ),
                Divider(height: 1, color: Colors.grey.withOpacity(0.3)),
                _buildSwitchTile(
                  icon: Icons.star,
                  title: 'Fluzar Score',
                  value: _showViralystScore,
                  onChanged: (value) async {
                    setState(() {
                      _showViralystScore = value;
                    });
                    try {
                      await _savePrivacySettings();
                    } catch (e) {
                      setState(() {
                        _showViralystScore = !value;
                      });
                    }
                  },
                ),
                Divider(height: 1, color: Colors.grey.withOpacity(0.3)),
                _buildSwitchTile(
                  icon: Icons.video_library,
                  title: 'Number of videos',
                  value: _showVideoCount,
                  onChanged: (value) async {
                    setState(() {
                      _showVideoCount = value;
                    });
                    try {
                      await _savePrivacySettings();
                    } catch (e) {
                      setState(() {
                        _showVideoCount = !value;
                      });
                    }
                  },
                ),
                Divider(height: 1, color: Colors.grey.withOpacity(0.3)),
                _buildSwitchTile(
                  icon: Icons.favorite,
                  title: 'Total likes',
                  value: _showLikeCount,
                  onChanged: (value) async {
                    setState(() {
                      _showLikeCount = value;
                    });
                    try {
                      await _savePrivacySettings();
                    } catch (e) {
                      setState(() {
                        _showLikeCount = !value;
                      });
                    }
                  },
                ),
                Divider(height: 1, color: Colors.grey.withOpacity(0.3)),
                _buildSwitchTile(
                  icon: Icons.comment,
                  title: 'Number of comments',
                  value: _showCommentCount,
                  onChanged: (value) async {
                    setState(() {
                      _showCommentCount = value;
                    });
                    try {
                      await _savePrivacySettings();
                    } catch (e) {
                      setState(() {
                        _showCommentCount = !value;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Row(
        children: [
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
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF667eea),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildPrivacySectionForModal(ThemeData theme, StateSetter setModalState) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
                child: Icon(Icons.security, color: Colors.white, size: 24),
              ),
              SizedBox(width: 12),
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
                  'Privacy Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsVisibilitySectionForModal(ThemeData theme, StateSetter setModalState) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
                child: Icon(Icons.visibility, color: Colors.white, size: 24),
              ),
              SizedBox(width: 12),
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
                  'Profile and Statistics Visibility',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Choose what to show to other users who are not your friends, only your friends can see the complete information.',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          SizedBox(height: 20),
          
          Container(
            decoration: BoxDecoration(
              // Effetto vetro semi-trasparente opaco per il contenitore interno
              color: isDark 
                  ? Colors.white.withOpacity(0.1) 
                  : Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark 
                    ? Colors.white.withOpacity(0.2)
                    : Colors.white.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark 
                      ? Colors.black.withOpacity(0.2)
                      : Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildSwitchTileForModal(
                  icon: Icons.person,
                  title: 'Top and recent videos',
                  value: _isProfilePublic,
                  onChanged: (value) async {
                    setModalState(() {
                      _isProfilePublic = value;
                    });
                    try {
                      await _savePrivacySettings();
                    } catch (e) {
                      setModalState(() {
                        _isProfilePublic = !value;
                      });
                    }
                  },
                ),
                Divider(height: 1, color: Colors.grey.withOpacity(0.3)),
                _buildSwitchTileForModal(
                  icon: Icons.star,
                  title: 'Fluzar Score',
                  value: _showViralystScore,
                  onChanged: (value) async {
                    setModalState(() {
                      _showViralystScore = value;
                    });
                    try {
                      await _savePrivacySettings();
                    } catch (e) {
                      setModalState(() {
                        _showViralystScore = !value;
                      });
                    }
                  },
                ),
                Divider(height: 1, color: Colors.grey.withOpacity(0.3)),
                _buildSwitchTileForModal(
                  icon: Icons.video_library,
                  title: 'Number of videos',
                  value: _showVideoCount,
                  onChanged: (value) async {
                    setModalState(() {
                      _showVideoCount = value;
                    });
                    try {
                      await _savePrivacySettings();
                    } catch (e) {
                      setModalState(() {
                        _showVideoCount = !value;
                      });
                    }
                  },
                ),
                Divider(height: 1, color: Colors.grey.withOpacity(0.3)),
                _buildSwitchTileForModal(
                  icon: Icons.favorite,
                  title: 'Total likes',
                  value: _showLikeCount,
                  onChanged: (value) async {
                    setModalState(() {
                      _showLikeCount = value;
                    });
                    try {
                      await _savePrivacySettings();
                    } catch (e) {
                      setModalState(() {
                        _showLikeCount = !value;
                      });
                    }
                  },
                ),
                Divider(height: 1, color: Colors.grey.withOpacity(0.3)),
                _buildSwitchTileForModal(
                  icon: Icons.comment,
                  title: 'Number of comments',
                  value: _showCommentCount,
                  onChanged: (value) async {
                    setModalState(() {
                      _showCommentCount = value;
                    });
                    try {
                      await _savePrivacySettings();
                    } catch (e) {
                      setModalState(() {
                        _showCommentCount = !value;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSwitchTileForModal({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Row(
        children: [
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
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF667eea),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  void _syncThemeWithSystem({Brightness? brightness}) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final resolvedBrightness = brightness ?? WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final shouldUseDark = resolvedBrightness == Brightness.dark;
    themeProvider.setDarkMode(shouldUseDark);
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (!mounted) return;
    _syncThemeWithSystem();
  }

  // Funzione per attivare il full screen
  Future<void> _enableFullScreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  // Funzione per disattivare il full screen
  Future<void> _disableFullScreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark 
          ? Color(0xFF121212) 
          : Colors.grey[50],
      body: Stack(
        children: [
          // Main content area - no padding, content can scroll behind floating header
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 100, 16, 16), // Aggiunto padding superiore per la top bar
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Jacopo buttons
                      if (_isJacopo)
                        Column(
                          children: [
                            ElevatedButton.icon(
                              icon: Icon(Icons.fullscreen),
                              label: Text('Abilita Full Screen'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                minimumSize: Size(double.infinity, 48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _enableFullScreen,
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              icon: Icon(Icons.fullscreen_exit),
                              label: Text('Disabilita Full Screen'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[700],
                                foregroundColor: Colors.white,
                                minimumSize: Size(double.infinity, 48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _disableFullScreen,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      
                      // Account and Security Section
                      _buildSection(
                        context,
                        'Account and Security',
                        [
                          // Profile button - visible only for authorized users
                          if (_isAuthorizedUser)
                            _buildAnimatedTile(
                              context,
                              'Profile',
                              Icons.person_outline,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ProfilePage(),
                                  ),
                                );
                              },
                            ),
                          _buildAnimatedTile(
                            context,
                            'Privacy Settings',
                            Icons.privacy_tip_outlined,
                            onTap: _showPrivacySettings,
                          ),
                          _buildAnimatedTile(
                            context,
                            'Change/Secure Password',
                            Icons.lock_outline,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ChangePasswordPage(),
                                ),
                              );
                            },
                          ),
                          // Credits button - visible only for non-premium users
                          if (!_isPremium)
                            _buildAnimatedTile(
                              context,
                              'Credits',
                              Icons.stars_outlined,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const CreditsPage(),
                                  ),
                                );
                              },
                            ),
                          _buildAnimatedTile(
                            context,
                            'Referral Code',
                            Icons.card_giftcard_outlined,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ReferralCodePage(),
                                ),
                              );
                            },
                          ),
                          if (!Platform.isIOS)
                            _buildAnimatedTile(
                              context,
                              'Payment',
                              Icons.payment_outlined,
                              onTap: _handlePaymentRedirect,
                            ),
                          if (_isAuthorizedUser)
                            _buildAnimatedTile(
                              context,
                              'Upgrade Premium (iOS)',
                              Icons.workspace_premium_outlined,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const UpgradePremiumIOSPage(),
                                  ),
                                );
                              },
                            ),
                          _buildAnimatedTile(
                            context,
                            'Delete Account',
                            Icons.delete_outline,
                            onTap: _showDeleteAccountDialog,
                            textColor: Colors.red,
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // App Preferences Section
                      _buildSection(
                        context,
                        'App Preferences',
                        [
                          _buildAnimatedTile(
                            context,
                            'Theme (Light/Dark)',
                            Icons.dark_mode_outlined,
                            trailing: Switch(
                              value: themeProvider.isDarkMode,
                              activeColor: const Color(0xFF667eea),
                              onChanged: (value) {
                                themeProvider.setDarkMode(value);
                              },
                            ),
                          ),
                          // Toggle lingua analisi IA
                          _buildAnimatedTile(
                            context,
                            'Language Analysis AI',
                            Icons.language,
                            trailing: Text(_languages[_selectedLanguage]!, style: TextStyle(fontWeight: FontWeight.w500)),
                            onTap: _showLanguagePicker,
                          ),
                          _buildAnimatedTile(
                            context,
                            'Troubleshooting',
                            Icons.build_outlined,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const TroubleshootingPage(),
                                ),
                              );
                            },
                          ),
                          _buildAnimatedTile(
                            context,
                            'Send Feedback',
                            Icons.feedback_outlined,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ContactSupportPage(),
                                ),
                              );
                            },
                          ),
                          // RIMOSSO: Toggle Push Notifications
                          // _buildAnimatedTile(
                          //   context,
                          //   'Push Notifications',
                          //   Icons.notifications_outlined,
                          //   trailing: Switch(
                          //     value: _notificationsEnabled,
                          //     activeColor: theme.colorScheme.primary,
                          //     onChanged: (value) {
                          //       setState(() {
                          //         _notificationsEnabled = value;
                          //       });
                          //     },
                          //   ),
                          // ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Legal Information Section
                      _buildSection(
                        context,
                        'Legal Information',
                        [
                          _buildAnimatedTile(
                            context,
                            'Terms and Conditions',
                            Icons.description_outlined,
                            onTap: () async {
                              const url = 'https://fluzar.com/terms-conditions';
                              if (await canLaunchUrl(Uri.parse(url))) {
                                await launchUrl(Uri.parse(url));
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Could not open Terms and Conditions')),
                                );
                              }
                            },
                          ),
                          _buildAnimatedTile(
                            context,
                            'Privacy Policy',
                            Icons.privacy_tip_outlined,
                            onTap: () async {
                              const url = 'https://fluzar.com/privacy-policy';
                              if (await canLaunchUrl(Uri.parse(url))) {
                                await launchUrl(Uri.parse(url));
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Could not open Privacy Policy')),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // About and Share Section
                      _buildSection(
                        context,
                        'About and Share',
                        [
                          _buildAnimatedTile(
                            context,
                            'About Fluzar',
                            Icons.info_outline,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AboutPage(),
                                ),
                              );
                            },
                          ),
                          _buildAnimatedTile(
                            context,
                            'How to Upload Videos',
                            Icons.upload_file,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const UploadingVideosPage(),
                                ),
                              );
                            },
                          ),
                          _buildAnimatedTile(
                            context,
                            'How to Schedule Videos',
                            Icons.schedule,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SchedulingVideosPage(),
                                ),
                              );
                            },
                          ),
                          _buildAnimatedTile(
                            context,
                            'Share App',
                            Icons.share_outlined,
                            onTap: _shareApp,
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 40),
                      

                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Floating header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _buildHeader(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
            child: ShaderMask(
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
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Divider(
            color: isDark 
                ? Colors.white.withOpacity(0.2)
                : Colors.white.withOpacity(0.3),
            thickness: 1,
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildAnimatedTile(
    BuildContext context,
    String title,
    IconData icon, {
    Widget? trailing,
    VoidCallback? onTap,
    Color? textColor,
  }) {
    final theme = Theme.of(context);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
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
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: textColor ?? theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (trailing != null) 
                trailing
              else if (onTap != null)
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey[400],
                  size: 16,
                ),
            ],
          ),
        ),
      ),
    );
  }
} 
