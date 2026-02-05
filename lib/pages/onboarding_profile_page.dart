import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'dart:ui';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';
import 'home_page.dart';
import '../main.dart';
import '../services/email_service.dart';

/// Pagina di onboarding per la selezione delle informazioni utente dopo la registrazione
class OnboardingProfilePage extends StatefulWidget {
  const OnboardingProfilePage({super.key});

  @override
  State<OnboardingProfilePage> createState() => _OnboardingProfilePageState();
}

class _OnboardingProfilePageState extends State<OnboardingProfilePage> with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  
  // Controllers per i campi di testo
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final FocusNode _displayNameFocusNode = FocusNode();
  final FocusNode _usernameFocusNode = FocusNode();
  
  // Variabili di stato
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isUploadingImage = false;
  
  
  // Username validation
  bool _isCheckingUsername = false;
  bool _isUsernameAvailable = true;
  String _usernameErrorMessage = '';
  bool _isUsernameManuallyEdited = false; // Flag per controllare se l'username è stato modificato manualmente
  Timer? _autoFillTimer; // Timer per debounce dell'auto-fill
  
  // Step management
  int _currentStep = 1; // Inizia con lo step 1 (Display Name)
  int _totalSteps = 3; // 3 step: Display Name, Username, Profile Picture
  int _effectiveProgressStep = 0; // Progresso effettivo per la barra di progresso - inizia da 0
  
  // Step animation controller
  late AnimationController _stepAnimationController;
  late Animation<double> _stepAnimation;
  
  // Progress bar animation controller
  late AnimationController _progressAnimationController;
  late Animation<double> _progressAnimation;
  
  // Progress number animation (stile jackpot)
  int _displayedProgress = 0;
  late AnimationController _progressNumberController;
  late Animation<double> _progressNumberAnimation;
  
  

  
  // Immagini
  File? _selectedProfileImage;
  String? _currentProfileImageUrl;
  final ImagePicker _picker = ImagePicker();
  
  // Animazioni
  late AnimationController _fadeAnimationController;
  late AnimationController _slideAnimationController;
  late AnimationController _pageTransitionController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pageTransitionAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
    _initializeAnimations();
    _loadExistingData();
    
    // Aggiungi listener per aggiornare lo stato quando il display name cambia
    _displayNameController.addListener(() {
      setState(() {});
      // Auto-compila l'username quando il display name cambia con debounce
      _autoFillTimer?.cancel();
      _autoFillTimer = Timer(Duration(milliseconds: 800), () {
        _autoFillUsername();
      });
    });
    
    // Aggiungi listener per aggiornare lo stato quando l'username cambia
    _usernameController.addListener(() {
      setState(() {});
      // Marca l'username come modificato manualmente
      _isUsernameManuallyEdited = true;
    });
    
    // Listener per aggiornare il progresso quando il display name è valido
    _displayNameController.addListener(() {
      // Non aggiornare il progresso mentre si sta scrivendo
      // Il progresso verrà aggiornato quando la tastiera si chiude
    });
    
    // Listener per il focus del display name - aggiorna il progresso quando la tastiera si chiude
    _displayNameFocusNode.addListener(() {
      if (!_displayNameFocusNode.hasFocus && _currentStep == 1) {
        // La tastiera si è chiusa, controlla se c'è del testo
        setState(() {
          if (_displayNameController.text.trim().isNotEmpty) {
            _effectiveProgressStep = 1; // Progresso 33% (step 1 completato)
          } else {
            _effectiveProgressStep = 0; // Progresso 0% se vuoto
          }
          // Avvia l'animazione progressiva
          _startProgressNumberAnimation();
        });
      }
    });
    
    // Listener per il focus dell'username - aggiorna il progresso quando la tastiera si chiude
    _usernameFocusNode.addListener(() {
      if (!_usernameFocusNode.hasFocus && _currentStep == 2) {
        // La tastiera si è chiusa, controlla se c'è del testo e se è valido
        setState(() {
          if (_usernameController.text.trim().isNotEmpty && _isUsernameAvailable) {
            _effectiveProgressStep = 2; // Progresso 66% (step 2 completato)
          } else {
            _effectiveProgressStep = 1; // Progresso 33% se vuoto o non valido
          }
          // Avvia l'animazione progressiva
          _startProgressNumberAnimation();
        });
      }
    });
    
    // Aggiorna il progresso per la sezione 3 quando cambia l'immagine del profilo
    // Questo verrà chiamato quando _selectedProfileImage cambia
    

  }

  void _initializeAnimations() {
    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _slideAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _stepAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _pageTransitionController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    // Progress number animation controller
    _progressNumberController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeAnimationController,
      curve: Curves.easeOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideAnimationController,
      curve: Curves.easeOutCubic,
    ));
    
    _stepAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _stepAnimationController,
      curve: Curves.easeOutCubic,
    ));
    
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _progressAnimationController,
      curve: Curves.easeOutCubic,
    ));
    
    // Progress number animation
    _progressNumberAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _progressNumberController,
      curve: Curves.easeOutCubic,
    ));
    
    _pageTransitionAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pageTransitionController,
      curve: Curves.easeInOutBack,
    ));
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.elasticOut,
    ));
    
    _fadeAnimationController.forward();
    _slideAnimationController.forward();
    _stepAnimationController.forward();
    _progressAnimationController.forward();
    _pageTransitionController.forward();
    _pulseController.repeat(reverse: true);
    
    // Initialize progress number at 0
    _displayedProgress = 0;
    
    // Listener per aggiornare il valore visualizzato durante l'animazione del numero
    _progressNumberAnimation.addListener(() {
      setState(() {
        _displayedProgress = _progressNumberAnimation.value.round();
      });
    });
  }

  // Verifica immediata se l'onboarding è già stato completato
  Future<void> _checkOnboardingStatus() async {
    if (_currentUser == null) return;

    try {
      final profileSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('onboardingCompleted')
          .get();
      
      final onboardingCompleted = profileSnapshot.value as bool? ?? false;
      
      if (onboardingCompleted && mounted) {
        // Se l'onboarding è già completato, naviga immediatamente alla main screen
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const MainScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } catch (e) {
      print('Error checking onboarding status: $e');
      // Continua con l'onboarding se c'è un errore
    }
  }

  @override
  void dispose() {
    _fadeAnimationController.dispose();
    _slideAnimationController.dispose();
    _stepAnimationController.dispose();
    _progressAnimationController.dispose();
    _pageTransitionController.dispose();
    _pulseController.dispose();
    _progressNumberController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _displayNameFocusNode.dispose();
    _usernameFocusNode.dispose();

    _autoFillTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadExistingData() async {
    if (_currentUser == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Carica dati utente esistenti
      final userSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .get();

      if (userSnapshot.exists) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        
        // Carica dati profilo se esistono
        final profileSnapshot = await _database
            .child('users')
            .child('users')
            .child(_currentUser!.uid)
            .child('profile')
            .get();
            
        Map<String, dynamic> profileData = {};
        String? profileImageUrl = userData['profileImageUrl'];
        
        if (profileSnapshot.exists) {
          profileData = Map<String, dynamic>.from(profileSnapshot.value as Map<dynamic, dynamic>);
          profileImageUrl = profileData['profileImageUrl'] ?? profileImageUrl;
          
          // Controlla se l'onboarding è già stato completato con controllo più robusto
          final onboardingCompleted = profileData['onboardingCompleted'] as bool? ?? false;
          if (onboardingCompleted && mounted) {
            // Se l'onboarding è già completato, naviga direttamente alla main screen
            print('Onboarding già completato, navigazione a MainScreen');
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const MainScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                },
                transitionDuration: const Duration(milliseconds: 500),
              ),
            );
            return; // Esci dalla funzione
          }
        }
        
        setState(() {
          _usernameController.text = profileData['username'] ?? userData['username'] ?? '';
          _displayNameController.text = profileData['displayName'] ?? userData['displayName'] ?? '';

          _currentProfileImageUrl = profileImageUrl;
          // Reset del flag di modifica manuale quando si caricano dati esistenti
          _isUsernameManuallyEdited = false;
          
          // Aggiorna il progresso iniziale in base ai dati esistenti
          if (_displayNameController.text.trim().isNotEmpty) {
            _effectiveProgressStep = 1; // Progresso 33% se c'è display name
          } else {
            _effectiveProgressStep = 0; // Progresso 0% se non c'è display name
          }
          
          // Avvia l'animazione progressiva iniziale
          _startInitialProgressAnimation();
        });
      }
    } catch (e) {
      print('Error loading existing data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Controlla se l'username è disponibile
  Future<void> _checkUsernameAvailability(String username) async {
    if (username.trim().isEmpty) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = true;
        _usernameErrorMessage = '';
      });
      return;
    }

    // Se l'username è lo stesso dell'utente corrente, è sempre disponibile
    if (_currentUser != null) {
      final currentUserSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .get();
      
      if (currentUserSnapshot.exists) {
        final userData = currentUserSnapshot.value as Map<dynamic, dynamic>;
        final currentUsername = userData['username'] ?? '';
        
        // Controlla anche nel profilo
        final profileSnapshot = await _database
            .child('users')
            .child('users')
            .child(_currentUser!.uid)
            .child('profile')
            .get();
            
        String profileUsername = '';
        if (profileSnapshot.exists) {
          final profileData = profileSnapshot.value as Map<dynamic, dynamic>;
          profileUsername = profileData['username'] ?? '';
        }
        
        if (username.trim().toLowerCase() == currentUsername.toLowerCase() || 
            username.trim().toLowerCase() == profileUsername.toLowerCase()) {
          setState(() {
            _isCheckingUsername = false;
            _isUsernameAvailable = true;
            _usernameErrorMessage = '';
          });
          return;
        }
      }
    }

    setState(() {
      _isCheckingUsername = true;
    });

    try {
      // Controlla se l'username esiste già nel database
      final usernameQuery = await _database
          .child('users')
          .child('users')
          .orderByChild('username')
          .equalTo(username.trim().toLowerCase())
          .get();

      // Controlla anche nel campo profile.username
      final profileUsernameQuery = await _database
          .child('users')
          .child('users')
          .orderByChild('profile/username')
          .equalTo(username.trim().toLowerCase())
          .get();

      bool isAvailable = true;
      String errorMessage = '';

      // Se trova risultati, l'username non è disponibile
      if (usernameQuery.exists && usernameQuery.children.isNotEmpty) {
        // Controlla se il risultato trovato è dell'utente corrente
        bool isCurrentUser = false;
        for (final child in usernameQuery.children) {
          if (child.key == _currentUser?.uid) {
            isCurrentUser = true;
            break;
          }
        }
        
        if (!isCurrentUser) {
          isAvailable = false;
          errorMessage = 'Username already in use';
        }
      }

      // Controlla anche nel campo profile.username
      if (profileUsernameQuery.exists && profileUsernameQuery.children.isNotEmpty) {
        // Controlla se il risultato trovato è dell'utente corrente
        bool isCurrentUser = false;
        for (final child in profileUsernameQuery.children) {
          if (child.key == _currentUser?.uid) {
            isCurrentUser = true;
            break;
          }
        }
        
        if (!isCurrentUser) {
          isAvailable = false;
          errorMessage = 'Username already in use';
        }
      }

      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = isAvailable;
        _usernameErrorMessage = errorMessage;
      });
    } catch (e) {
      print('Error checking username availability: $e');
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameErrorMessage = 'Errore nel controllo username';
      });
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


  /// Gestisce i permessi di sistema per fotocamera e galleria
  Future<bool> _handleMediaPermissions(ImageSource source) async {
    PermissionStatus status = PermissionStatus.granted;
    bool isAndroid = false;
    bool isIOS = false;
    
    try {
      isAndroid = Theme.of(context).platform == TargetPlatform.android;
      isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    } catch (_) {}

    if (source == ImageSource.camera) {
      // Richiedi permesso fotocamera
      if (isIOS) {
        print('[PERMISSION] iOS: controllo se permesso fotocamera già concesso...');
        final cameraGranted = await Permission.camera.isGranted;
        if (cameraGranted) {
          status = PermissionStatus.granted;
        } else {
          print('[PERMISSION] iOS: permesso non concesso, ma lascio che image_picker gestisca la richiesta...');
          // Su iOS, non richiediamo il permesso qui - lasciamo che image_picker lo gestisca
          // Questo evita il popup "Permission required" e permette i dialoghi di sistema reali
          status = PermissionStatus.granted;
        }
      } else {
        print('[PERMISSION] Android/Altro: richiedo permesso fotocamera...');
        status = await Permission.camera.request();
      }
      
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          _showErrorSnackBar('Camera permission required to take photos', showSettingsButton: true);
        } else {
          _showErrorSnackBar('Camera permission required to take photos');
        }
        return false;
      }
    } else {
      // Richiedi permesso galleria/foto
      if (isAndroid) {
        print('[PERMISSION] Android: richiedo permesso galleria...');
        final photosGranted = await Permission.photos.isGranted;
        final storageGranted = await Permission.storage.isGranted;
        
        if (photosGranted || storageGranted) {
          status = PermissionStatus.granted;
        } else {
          // Prova prima con photos, poi con storage per compatibilità
          status = await Permission.photos.request();
          if (!status.isGranted) {
            status = await Permission.storage.request();
          }
        }
      } else if (isIOS) {
        print('[PERMISSION] iOS: controllo se permesso galleria già concesso...');
        final photosGranted = await Permission.photos.isGranted;
        if (photosGranted) {
          status = PermissionStatus.granted;
        } else {
          print('[PERMISSION] iOS: permesso non concesso, ma lascio che image_picker gestisca la richiesta...');
          // Su iOS, non richiediamo il permesso qui - lasciamo che image_picker lo gestisca
          // Questo evita il popup "Permission required" e permette i dialoghi di sistema reali
          status = PermissionStatus.granted;
        }
      } else {
        status = await Permission.photos.request();
      }
      
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          _showErrorSnackBar('Gallery permission required to select photos', showSettingsButton: true);
        } else {
          _showErrorSnackBar('Gallery permission required to select photos');
        }
        return false;
      }
    }
    
    return true;
  }

  Future<void> _pickProfileImage(ImageSource source) async {
    try {
      // Prima controlla e richiedi i permessi necessari
      bool hasPermission = await _handleMediaPermissions(source);
      if (!hasPermission) {
        return; // Esci se i permessi non sono stati concessi
      }
      
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      
      if (image != null) {
        setState(() {
          _selectedProfileImage = File(image.path);
          // Aggiorna il progresso per la sezione 3 quando l'immagine è selezionata
          if (_currentStep == 3) {
            _effectiveProgressStep = 3; // Progresso 100% (step 3 completato)
            // Avvia l'animazione progressiva
            _startProgressNumberAnimation();
          }
        });
      }
    } catch (e) {
      print('Error picking profile image: $e');
      _showErrorSnackBar('Error selecting profile image');
    }
  }

  Future<String?> _uploadProfileImage() async {
    if (_selectedProfileImage == null) return _currentProfileImageUrl;

    try {
      setState(() {
        _isUploadingImage = true;
      });

      // Cloudflare R2 credentials
      final String accessKeyId = '5e181628bad7dc5481c92c6f3899efd6';
      final String secretKey = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
      final String endpoint = 'https://3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com';
      final String bucketName = 'videos';
      final String accountId = '3d945eb681944ec5965fecf275e41a9b';
      final String region = 'auto';
      
      // Generate a unique filename for profile image
      final String fileExtension = path.extension(_selectedProfileImage!.path);
      final String fileName = 'profile_${_currentUser!.uid}_${DateTime.now().millisecondsSinceEpoch}$fileExtension';
      final String fileKey = 'profile_images/$fileName';
      
      // Get file bytes and size
      final bytes = await _selectedProfileImage!.readAsBytes();
      final contentLength = bytes.length;
      
      // Calcola l'hash SHA-256 del contenuto
      final List<int> contentHash = sha256.convert(bytes).bytes;
      final String payloadHash = hex.encode(contentHash);
      
      // Set up request information
      final String httpMethod = 'PUT';
      final String contentType = 'image/jpeg';
      
      // SigV4 richiede data in formato ISO8601
      final now = DateTime.now().toUtc();
      final String amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
      final String dateStamp = DateFormat("yyyyMMdd").format(now);
      
      // Host e URI
      final Uri uri = Uri.parse('$endpoint/$bucketName/$fileKey');
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
      
      // Ordina gli header in ordine lessicografico
      final sortedHeaderKeys = headers.keys.toList()..sort();
      for (final key in sortedHeaderKeys) {
        canonicalHeaders += '${key.toLowerCase()}:${headers[key]}\n';
        signedHeaders += '${key.toLowerCase()};';
      }
      signedHeaders = signedHeaders.substring(0, signedHeaders.length - 1);
      
      // Canonical request
      final String canonicalUri = '/$bucketName/$fileKey';
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
      
      // Create request URL
      final String uploadUrl = '$endpoint/$bucketName/$fileKey';
      
      // Create request with headers
      final http.Request request = http.Request('PUT', Uri.parse(uploadUrl));
      request.headers['Host'] = host;
      request.headers['Content-Type'] = contentType;
      request.headers['Content-Length'] = contentLength.toString();
      request.headers['X-Amz-Content-Sha256'] = payloadHash;
      request.headers['X-Amz-Date'] = amzDate;
      request.headers['Authorization'] = authorizationHeader;
      
      // Add file body
      request.bodyBytes = bytes;
      
      // Send the request
      final response = await http.Client().send(request);
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Generate public URL
        final String publicUrl = 'https://pub-$accountId.r2.dev/$fileKey';
        
        print('Immagine profilo caricata con successo su Cloudflare R2');
        print('URL pubblico generato: $publicUrl');
        
        return publicUrl;
      } else {
        throw Exception('Errore nel caricamento su Cloudflare R2: Codice ${response.statusCode}, Risposta: $responseBody');
      }
    } catch (e) {
      print('Error uploading profile image: $e');
      _showErrorSnackBar('Error uploading profile image');
      return _currentProfileImageUrl;
    } finally {
      setState(() {
        _isUploadingImage = false;
      });
    }
  }



  Future<void> _saveProfile() async {
    if (_currentUser == null) return;

    // Controlla se l'username è valido
    if (_usernameController.text.trim().isEmpty) {
      _showErrorSnackBar('Username is required');
      return;
    }

    // Controlla se l'username è disponibile
    if (!_isUsernameAvailable) {
      _showErrorSnackBar('Username not available. Please choose another one.');
      return;
    }

    // Se l'username è in fase di controllo, aspetta
    if (_isCheckingUsername) {
      _showErrorSnackBar('Please wait for username validation...');
      return;
    }
    


    setState(() {
      _isSaving = true;
    });

    try {
      // Upload immagine profilo se selezionata
      String? profileImageUrl = await _uploadProfileImage();
      
      // Prepara i dati del profilo
      final profileData = {
        'username': _usernameController.text.trim().toLowerCase(), // Salva sempre in lowercase
        'displayName': _displayNameController.text.trim(),
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        'onboardingCompleted': true, // Marca l'onboarding come completato
      };
      
      // Aggiungi l'immagine profilo se presente
      if (profileImageUrl != null) {
        profileData['profileImageUrl'] = profileImageUrl;
        profileData['profileImageUploadedAt'] = DateTime.now().millisecondsSinceEpoch;
        profileData['profileImageSource'] = 'cloudflare_r2';
      }
      
      // Salva i dati del profilo (usa update per preservare dati esistenti come alreadyfriends)
      await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .update(profileData);
          
      print('Dati profilo salvati in Firebase');
      
      // Verifica che onboardingCompleted sia stato salvato correttamente
      final verifySnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('onboardingCompleted')
          .get();
      
      final savedOnboardingStatus = verifySnapshot.value as bool? ?? false;
      print('Verifica onboardingCompleted salvato: $savedOnboardingStatus');
      
      // Aggiorna il display name di Firebase Auth se necessario
      if (_displayNameController.text.trim().isNotEmpty) {
        await _currentUser!.updateDisplayName(_displayNameController.text.trim());
      }

      // Invia email di benvenuto con il displayName scelto dall'utente
      try {
        if (_currentUser!.email != null && _currentUser!.email!.isNotEmpty) {
          final displayName = _displayNameController.text.trim();
          if (displayName.isNotEmpty) {
            await EmailService.sendWelcomeEmail(_currentUser!.email!, displayName);
            print('Email di benvenuto inviata con successo a: ${_currentUser!.email!}');
          }
        }
      } catch (e) {
        print('Errore nell\'invio email di benvenuto: $e');
        // Non bloccare il completamento del setup se l'email fallisce
      }

      // Naviga alla pagina principale
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => MainScreen(initialArguments: null),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (e) {
      print('Error saving profile: $e');
      _showErrorSnackBar('Error saving profile');
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }
  
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF00BFA6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
      ),
    );
  }
  
  void _showErrorSnackBar(String message, {bool showSettingsButton = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
            if (showSettingsButton) ...[
              SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    await openAppSettings();
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'Settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
        duration: showSettingsButton ? Duration(seconds: 5) : Duration(seconds: 3),
      ),
    );
  }
  
  /// Gestisce il completamento dello step finale (step 3)
  Future<void> _handleCompleteStep() async {
    await _saveProfile();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps) {
      // Animazione di transizione fluida
      _pageTransitionController.reset();
      _pageTransitionController.forward();
      
      // Effetto di "viaggio" con delay
      Future.delayed(Duration(milliseconds: 300), () {
      setState(() {
        _currentStep++;
          // Aggiorna il progresso effettivo quando si va avanti
          if (_currentStep == 3) {
            // Se siamo al step 3, il progresso dipende se l'immagine è selezionata
            _effectiveProgressStep = (_selectedProfileImage != null || (_currentProfileImageUrl != null && _currentProfileImageUrl!.isNotEmpty)) ? 3 : 2;
          } else {
            _effectiveProgressStep = _currentStep;
          }
          
          // Avvia l'animazione progressiva
          _startProgressNumberAnimation();
      });
        
        // Animazioni di entrata per il nuovo step
      _stepAnimationController.reset();
      _stepAnimationController.forward();
        
        // Anima la progress bar con effetto elastico
        _progressAnimationController.reset();
        _progressAnimationController.forward();
        
        // Avvia l'animazione progressiva dei numeri
        _startProgressNumberAnimation();
        
        // Effetto di celebrazione per il completamento dello step
        _pulseController.reset();
        _pulseController.forward();
      });
    }
  }
  


  void _previousStep() {
    if (_currentStep > 1) {
      // Animazione di transizione fluida
      _pageTransitionController.reset();
      _pageTransitionController.forward();
      
      // Effetto di "ritorno" con delay
      Future.delayed(Duration(milliseconds: 200), () {
      setState(() {
        _currentStep--;
          // Aggiorna il progresso effettivo quando si torna indietro
          if (_currentStep == 2) {
            // Se torniamo al step 2, controlla se l'username è valido
            if (_isUsernameAvailable && _usernameController.text.trim().isNotEmpty) {
              _effectiveProgressStep = 2; // Progresso 66%
            } else {
              _effectiveProgressStep = 1; // Progresso 33% (anche se vuoto)
            }
          } else {
            _effectiveProgressStep = _currentStep;
          }
          
          // Avvia l'animazione progressiva
          _startProgressNumberAnimation();
        });
        
        // Animazioni di entrata per il nuovo step
      _stepAnimationController.reset();
      _stepAnimationController.forward();
        
        // Anima la progress bar con effetto elastico
        _progressAnimationController.reset();
        _progressAnimationController.forward();
        
        // Avvia l'animazione progressiva dei numeri
        _startProgressNumberAnimation();
        
        // Reset del flag di modifica manuale quando si torna al primo step
        if (_currentStep == 1) {
          _isUsernameManuallyEdited = false;
        }
      });
    }
  }

  // Funzione per avviare l'animazione progressiva dei numeri
  void _startProgressNumberAnimation() {
    final totalSteps = _totalSteps;
    final currentProgress = _effectiveProgressStep;
    final targetProgress = (currentProgress / totalSteps * 100).round();
    
    // Reset and start animation
    _progressNumberAnimation = Tween<double>(
      begin: _displayedProgress.toDouble(),
      end: targetProgress.toDouble(),
    ).animate(CurvedAnimation(
      parent: _progressNumberController,
      curve: Curves.easeOutCubic,
    ));
    
    _progressNumberController.forward(from: 0);
  }
  
  // Funzione per avviare l'animazione progressiva iniziale
  void _startInitialProgressAnimation() {
    final targetProgress = (_effectiveProgressStep / _totalSteps * 100).round();
    _progressNumberAnimation = Tween<double>(
      begin: _displayedProgress.toDouble(),
      end: targetProgress.toDouble(),
    ).animate(CurvedAnimation(
      parent: _progressNumberController,
      curve: Curves.easeOutCubic,
    ));
    _progressNumberController.forward(from: 0);
  }

  // Funzione per auto-compilare l'username basandosi sul display name
  void _autoFillUsername() async {
    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) {
      // Se il display name è vuoto, pulisci l'username se non è stato modificato manualmente
      if (!_isUsernameManuallyEdited) {
        _usernameController.text = '';
      }
      return;
    }
    
    // Non auto-compilare se l'username è stato modificato manualmente
    if (_isUsernameManuallyEdited) return;
    
    // Crea un username base dal display name
    String baseUsername = displayName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '') // Mantieni lettere, numeri e spazi
        .replaceAll(RegExp(r'\s+'), ''); // Rimuovi spazi
    
    print('Display Name: "$displayName" -> Username: "$baseUsername"');
    
    // Se l'username base è vuoto dopo la pulizia, usa un fallback
    if (baseUsername.isEmpty) {
      baseUsername = 'user';
    }
    
    // Controlla se l'username base è disponibile
    bool isAvailable = await _checkUsernameAvailabilitySync(baseUsername);
    
    if (isAvailable) {
      // Se disponibile, usa quello
      _usernameController.text = baseUsername;
    } else {
      // Se non disponibile, prova con numeri
      String suggestedUsername = await _findAvailableUsername(baseUsername);
      _usernameController.text = suggestedUsername;
    }
  }
  
  // Funzione per controllare la disponibilità dell'username in modo sincrono
  Future<bool> _checkUsernameAvailabilitySync(String username) async {
    if (username.trim().isEmpty) return false;
    
    try {
      // Controlla se l'username esiste già nel database
      final usernameQuery = await _database
          .child('users')
          .child('users')
          .orderByChild('username')
          .equalTo(username.trim().toLowerCase())
          .get();

      // Controlla anche nel campo profile.username
      final profileUsernameQuery = await _database
          .child('users')
          .child('users')
          .orderByChild('profile/username')
          .equalTo(username.trim().toLowerCase())
          .get();

      // Se trova risultati, l'username non è disponibile
      if (usernameQuery.exists && usernameQuery.children.isNotEmpty) {
        // Controlla se il risultato trovato è dell'utente corrente
        bool isCurrentUser = false;
        for (final child in usernameQuery.children) {
          if (child.key == _currentUser?.uid) {
            isCurrentUser = true;
            break;
          }
        }
        
        if (!isCurrentUser) {
          return false;
        }
      }

      // Controlla anche nel campo profile.username
      if (profileUsernameQuery.exists && profileUsernameQuery.children.isNotEmpty) {
        // Controlla se il risultato trovato è dell'utente corrente
        bool isCurrentUser = false;
        for (final child in profileUsernameQuery.children) {
          if (child.key == _currentUser?.uid) {
            isCurrentUser = true;
            break;
          }
        }
        
        if (!isCurrentUser) {
          return false;
        }
      }

      return true;
    } catch (e) {
      print('Error checking username availability sync: $e');
      return false;
    }
  }
  
  // Funzione per trovare un username disponibile aggiungendo numeri
  Future<String> _findAvailableUsername(String baseUsername) async {
    // Prova con numeri da 1 a 999
    for (int i = 1; i <= 999; i++) {
      String suggestedUsername = '$baseUsername$i';
      bool isAvailable = await _checkUsernameAvailabilitySync(suggestedUsername);
      if (isAvailable) {
        return suggestedUsername;
      }
    }
    
    // Se non trova nulla, usa un timestamp
    return '${baseUsername}${DateTime.now().millisecondsSinceEpoch % 1000}';
  }

  // Funzione per determinare se il bottone deve essere disabilitato
  bool _isButtonDisabled() {
    if (_isSaving) return true;
    
    // Validazione specifica per step
    switch (_currentStep) {
      case 1: // Display Name - richiede display name
        return _displayNameController.text.trim().isEmpty;
      case 2: // Username - richiede username valido
        return _usernameController.text.trim().isEmpty || 
               !_isUsernameAvailable || 
               _isCheckingUsername;
      case 3: // Profile Picture - opzionale, sempre abilitato
        return false;
      default:
        return false;
    }
  }
  
  // Funzione per determinare se il bottone Complete deve essere disabilitato
  bool _isCompleteButtonDisabled() {
    if (_isSaving) return true;
    
    return _isButtonDisabled();
  }
  
  // Funzione per ottenere il testo del bottone Complete
  String _getCompleteButtonText() {
    if (_isSaving) return 'Setting up...';
    return _currentStep < 3 ? 'Next' : 'Complete';
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 1:
        return 'Display Name';
      case 2:
        return 'Username';
      case 3:
        return 'Profile Picture';
      case 4:
        return 'Optional Info';
      case 5:
        return 'Profile Preview';
      default:
        return 'Setup Profile';
    }
  }

  String _getStepDescription() {
    switch (_currentStep) {
      case 1:
        return Platform.isIOS 
            ? 'This is how others will see you.'
            : 'Enter your display name                This is how others will see you.';
      case 2:
        return 'Choose a unique username for your profile.';
      case 3:
        return 'Choose a profile picture that represents you best. This will be displayed on your profile. (Optional)';
      default:
        return 'Complete your profile setup';
    }
  }

  Widget _getCurrentStepContent(ThemeData theme) {
    switch (_currentStep) {
      case 1:
        return _buildDisplayNameStep(theme);
      case 2:
        return _buildUsernameStep(theme);
      case 3:
        return _buildProfileImageStep(theme);
      default:
        return _buildDisplayNameStep(theme);
    }
  }


  void _showProfileImagePickerDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Color(0xFF1E1E1E) 
                : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Select profile image',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildImagePickerButton(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(context);
                      _pickProfileImage(ImageSource.camera);
                    },
                  ),
                  _buildImagePickerButton(
                    icon: Icons.photo_library,
                    label: 'Photo Gallery',
                    onTap: () {
                      Navigator.pop(context);
                      _pickProfileImage(ImageSource.gallery);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildImagePickerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6C63FF),
                    const Color(0xFF8B7CF6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.3),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Controllo di sicurezza aggiuntivo per evitare che la pagina si mostri se l'onboarding è completato
    if (_currentUser == null) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: isDark ? Color(0xFF121212) : Colors.white,
      appBar: null,
      resizeToAvoidBottomInset: false, // Impedisce al contenuto di spostarsi quando appare la tastiera
      body: Stack(
        children: [
          // Main content area - no padding, content can scroll behind floating header
          SafeArea(
            child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Color(0xFF667eea),
                  ),
                  strokeWidth: 3,
                ),
              )
                : FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                        child: _currentStep == 1 || _currentStep == 2 || _currentStep == 3
                          ? _buildFirstStepLayout(theme) // Layout fisso per il primo, secondo e terzo step
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(24, 100, 24, 24), // Ridotto il padding bottom
                        child: Column(
                          children: [
                            // Progress indicator
                            _buildProgressIndicator(theme),
                            
                            SizedBox(height: 30),
                            
                            // Step content con animazioni avanzate
                            AnimatedBuilder(
                              animation: _pageTransitionAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: 0.95 + (_pageTransitionAnimation.value * 0.05),
                                  child: Transform.translate(
                                    offset: Offset(
                                      0,
                                      (1 - _pageTransitionAnimation.value) * 20,
                                    ),
                                    child: FadeTransition(
                              opacity: _stepAnimation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                          begin: const Offset(0, 0.3),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                  parent: _stepAnimationController,
                                  curve: Curves.easeOutCubic,
                                )),
                                child: _getCurrentStepContent(theme),
                              ),
                            ),
                                  ),
                                );
                              },
                            ),
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
          
          // Fixed button at bottom (con padding per evitare i tasti di sistema Android)
          Positioned(
            bottom: 0, // Rimosso il padding fisso di 38 pixel
            left: 0,
            right: 0,
              child: _buildFixedButton(theme),
            ),
        ],
      ),
    );
  }
  
  Widget _buildFirstStepLayout(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 100, 24, 24), // Ridotto il padding bottom
      child: Column(
        children: [
          // Progress indicator
          _buildProgressIndicator(theme),
          
          SizedBox(height: 30),
          
          // Step content con animazioni avanzate
          AnimatedBuilder(
            animation: _pageTransitionAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: 0.95 + (_pageTransitionAnimation.value * 0.05),
                child: Transform.translate(
                  offset: Offset(
                    0,
                    (1 - _pageTransitionAnimation.value) * 20,
                  ),
                  child: FadeTransition(
                    opacity: _stepAnimation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.3),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _stepAnimationController,
                        curve: Curves.easeOutCubic,
                      )),
                      child: _getCurrentStepContent(theme),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildProgressIndicator(ThemeData theme) {
    // Calcola il progresso per tutti gli step
    final int progressSteps = _totalSteps;
    final int currentProgressStep = _effectiveProgressStep;
    final double progress = currentProgressStep / progressSteps; // Cambiato per gestire il caso 0
    
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Step counter con animazione
              AnimatedSwitcher(
                duration: Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(0, -0.5),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    )),
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  );
                },
                child: Text(
                  'Step ${currentProgressStep == 0 ? 1 : currentProgressStep} of $progressSteps',
                  key: ValueKey(currentProgressStep),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
              ),
              
              // Percentuale con animazione
              AnimatedSwitcher(
                duration: Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.8,
                      end: 1.0,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.elasticOut,
                    )),
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  );
                },
                child: Text(
                '$_displayedProgress%',
                  key: ValueKey(_displayedProgress),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                          ),
                        ),
          ),
        ],
      ),
          SizedBox(height: 12),
          
          // Progress bar animata personalizzata
          AnimatedBuilder(
            animation: _progressAnimation,
            builder: (context, child) {
              final animatedProgress = progress * _progressAnimation.value;
              
              return Container(
                height: 8,
              decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Stack(
                      children: [
                    // Background
                    Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: theme.colorScheme.surfaceVariant,
                      ),
                    ),
                    
                    // Progress fill con gradiente
                    AnimatedContainer(
                      duration: Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      width: MediaQuery.of(context).size.width * 0.85 * animatedProgress,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF667eea),
                            Color(0xFF764ba2),
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF667eea).withOpacity(0.3),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    
                    // Effetto shimmer
                    if (animatedProgress > 0)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
            child: Container(
                          width: MediaQuery.of(context).size.width * 0.85 * animatedProgress,
              decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors: [
                                Colors.white.withOpacity(0.0),
                                Colors.white.withOpacity(0.3),
                                Colors.white.withOpacity(0.0),
                              ],
                              stops: [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                  ),
                ],
              ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFixedButton(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.4),
          width: 1,
        ),
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
        children: [
          // Previous button (solo se non siamo al primo step)
          if (_currentStep > 1)
            Container(
              width: 48,
              height: 48,
              margin: EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isDark 
                    ? Colors.white.withOpacity(0.15) 
                    : Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark 
                      ? Colors.white.withOpacity(0.2)
                      : Colors.white.withOpacity(0.4),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark 
                        ? Colors.black.withOpacity(0.2)
                        : Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _previousStep,
                  child: Center(
                    child: Icon(
                      Icons.arrow_back,
                      color: isDark ? Colors.white : Colors.black87,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          
          // Main button con stile identico al "Continue to Edit"
          Expanded(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isButtonDisabled() ? 1.0 : (0.98 + (_pulseAnimation.value * 0.02)),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: _isButtonDisabled()
                          ? null
                          : const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                              colors: [
                                Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                                Color(0xFF764ba2), // Colore finale: viola al 100%
                              ],
                            ),
                      color: _isButtonDisabled()
                          ? (isDark ? Colors.grey.withOpacity(0.2) : Colors.grey.withOpacity(0.15))
                          : null,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _isButtonDisabled()
                          ? null
                          : [
                              BoxShadow(
                                color: const Color(0xFF667eea).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _isCompleteButtonDisabled()
                            ? null 
                            : (_currentStep < 3 ? _nextStep : _handleCompleteStep),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                                                    child: _isSaving
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    _getCompleteButtonText(),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _getCompleteButtonText(),
                                    style: TextStyle(
                                      color: _isCompleteButtonDisabled()
                                          ? Colors.white.withOpacity(0.5)
                                          : Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(
                                    _currentStep < 3 ? Icons.arrow_forward : Icons.check,
                                    color: _isCompleteButtonDisabled()
                                        ? Colors.white.withOpacity(0.5)
                                        : Colors.white,
                                    size: 18,
                                  ),
                                ],
                              ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
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
            children: [
              SizedBox(width: 10), // Spazio di 5 pixel a sinistra
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
                  'FLUZAR',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                    fontFamily: 'Ethnocentric',
                  ),
                ),
              ),
              Spacer(), // Spazio flessibile a destra
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea).withOpacity(0.1),
                      Color(0xFF764ba2).withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  borderRadius: BorderRadius.circular(16),
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
                      transform: GradientRotation(135 * 3.14159 / 180),
                    ).createShader(bounds);
                  },
                  child: Text(
                    'Setup Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
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
  
    Widget _buildDisplayNameStep(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      children: [
        // Spazio sopra per centrare il card (ridotto di 1 cm) - iOS: 65px più in alto, Android: 30px più in alto
        SizedBox(height: MediaQuery.of(context).size.height * 0.15 - 40 - (Platform.isIOS ? 65 : (Platform.isAndroid ? 30 : 0))),
        
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: isDark 
                ? Colors.white.withOpacity(0.15) 
                : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark 
                  ? Colors.white.withOpacity(0.2)
                  : Colors.white.withOpacity(0.4),
              width: 1,
            ),
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
          padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                child: Text(
                  'Display Name',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                        fontSize: 24,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea).withOpacity(0.1),
                      Color(0xFF764ba2).withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  borderRadius: BorderRadius.circular(16),
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
                      transform: GradientRotation(135 * 3.14159 / 180),
                    ).createShader(bounds);
                  },
                  child: Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
              const SizedBox(height: 24),
          Text(
            _getStepDescription(),
            style: TextStyle(
              fontSize: 16,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                  height: 1.5,
            ),
                textAlign: TextAlign.left,
                softWrap: true,
          ),
              
              const SizedBox(height: 32),
          
          // Display name field
          TextFormField(
            controller: _displayNameController,
            focusNode: _displayNameFocusNode,
            maxLength: 15,
            decoration: InputDecoration(
              labelText: 'Display Name',
              hintText: 'Enter display name',
              prefixIcon: ShaderMask(
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
                child: Icon(Icons.person, color: Colors.white),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: isDark ? Colors.white.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: isDark ? Colors.white.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Color(0xFF667eea),
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            ),
          ),
        ],
      ),
        ),
        // Padding del 30% sotto al card
        SizedBox(height: MediaQuery.of(context).size.height * 0.01),
      ],
    );
  }
  
  // Funzione helper per creare il card semplice
  Widget _buildStepCardWithProgress({
    required Widget child,
    required int stepNumber,
    required ThemeData theme,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(top: 18, bottom: 10),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.4),
          width: 1,
        ),
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
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
  
  Widget _buildProfileImageStep(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
        children: [
        // Spazio sopra per centrare il card (ridotto di 2 cm)
        SizedBox(height: MediaQuery.of(context).size.height * 0.15 - 120),
        
              Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.4),
          width: 1,
        ),
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
          padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                child: Text(
                      'Profile Picture',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                        fontSize: 24,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea).withOpacity(0.1),
                      Color(0xFF764ba2).withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  borderRadius: BorderRadius.circular(16),
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
                      transform: GradientRotation(135 * 3.14159 / 180),
                    ).createShader(bounds);
                  },
                  child: Icon(
                        Icons.camera_alt,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
              const SizedBox(height: 24),
          Text(
            _getStepDescription(),
            style: TextStyle(
              fontSize: 16,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                  height: 1.5,
                ),
                textAlign: TextAlign.left,
                softWrap: true,
              ),
              
              const SizedBox(height: 32),
              
          Center(
            child: GestureDetector(
                  onTap: _showProfileImagePickerDialog,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surfaceVariant,
                  border: Border.all(
                    color: Color(0xFF667eea).withOpacity(0.3),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF667eea).withOpacity(0.2),
                      blurRadius: 15,
                      spreadRadius: 2,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                    child: _selectedProfileImage != null
                    ? ClipOval(
                        child: Image.file(
                              _selectedProfileImage!,
                          fit: BoxFit.cover,
                        ),
                      )
                        : _currentProfileImageUrl != null && _currentProfileImageUrl!.isNotEmpty
                        ? ClipOval(
                            child: Image.network(
                                  _currentProfileImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                      Icons.person,
                                  size: 60,
                                  color: Colors.grey[400],
                                );
                              },
                            ),
                          )
                        : Icon(
                                Icons.person,
                            size: 60,
                            color: Colors.grey[400],
                          ),
              ),
            ),
          ),
              
              const SizedBox(height: 24),
              
          Center(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF667eea).withOpacity(0.1),
                    Color(0xFF764ba2).withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  transform: GradientRotation(135 * 3.14159 / 180),
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: _showProfileImagePickerDialog,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
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
                          child: Icon(Icons.camera_alt, size: 18, color: Colors.white),
                        ),
                        SizedBox(width: 8),
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
                            'Add Photo',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
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
        ],
      ),
        ),
        // Padding del 20% sotto al card
        SizedBox(height: MediaQuery.of(context).size.height * 0.1),
      ],
    );
  }
  



  
  Widget _buildUsernameStep(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      children: [
        // Spazio sopra per centrare il card (ridotto di 2 cm) + 20 pixel in più - iOS: 45px più in alto
        SizedBox(height: MediaQuery.of(context).size.height * 0.15 - 60 - (Platform.isIOS ? 45 : 0)),
        
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.4),
          width: 1,
        ),
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
          padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                child: Text(
                  'Username',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                        fontSize: 24,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea).withOpacity(0.1),
                      Color(0xFF764ba2).withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  borderRadius: BorderRadius.circular(16),
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
                      transform: GradientRotation(135 * 3.14159 / 180),
                    ).createShader(bounds);
                  },
                  child: Icon(
                    Icons.alternate_email,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
              const SizedBox(height: 24),
          Text(
            _getStepDescription(),
            style: TextStyle(
              fontSize: 16,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                  height: 1.5,
            ),
                textAlign: TextAlign.left,
                softWrap: true,
          ),
              
              const SizedBox(height: 32),
          
          // Username field
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          TextFormField(
            controller: _usernameController,
            focusNode: _usernameFocusNode,
            maxLength: 15,
                onChanged: (value) {
                  // Controlla la disponibilità dell'username dopo un breve delay
                  Future.delayed(Duration(milliseconds: 500), () {
                    if (value == _usernameController.text) {
                      _checkUsernameAvailability(value);
                    }
                  });
                },
            decoration: InputDecoration(
              labelText: 'Username',
              hintText: 'Enter your username',
              prefixIcon: ShaderMask(
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
                child: Icon(Icons.alternate_email, color: Colors.white),
              ),
                  suffixIcon: _isCheckingUsername
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                          ),
                        )
                      : _usernameController.text.isNotEmpty
                          ? Icon(
                              _isUsernameAvailable ? Icons.check_circle : Icons.error,
                              color: _isUsernameAvailable ? Colors.green : Colors.red,
                              size: 20,
                            )
                          : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: isDark ? Colors.white.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                      color: _usernameController.text.isNotEmpty && !_isUsernameAvailable
                          ? Colors.red
                          : isDark ? Colors.white.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                      color: _usernameController.text.isNotEmpty && !_isUsernameAvailable
                          ? Colors.red
                          : Color(0xFF667eea),
                      width: 2,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.red,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            ),
              ),
              if (_usernameController.text.isNotEmpty && _usernameErrorMessage.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 8, left: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _usernameErrorMessage,
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_usernameController.text.isNotEmpty && _isUsernameAvailable && !_isCheckingUsername)
                Padding(
                  padding: EdgeInsets.only(top: 8, left: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Text(
                            'Username available',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_usernameController.text.isNotEmpty && !_isUsernameManuallyEdited)
                Padding(
                  padding: EdgeInsets.only(top: 8, left: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: Color(0xFF667eea),
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Text(
                            'Username suggested by AI',
                        style: TextStyle(
                          color: Color(0xFF667eea),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
        ),
        // Padding del 30% sotto al card
        SizedBox(height: MediaQuery.of(context).size.height * 0.0),
      ],
    );
  }
}



 