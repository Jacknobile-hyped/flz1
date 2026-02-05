import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../services/youtube_service.dart';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:image/image.dart' as img; // For Instagram image processing
import 'package:path/path.dart' as path; // For path operations
import 'package:google_sign_in/google_sign_in.dart';

// Custom circular progress painter for scheduling visualization
class CircularProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color color;
  final bool smoothTransition;

  CircularProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    this.smoothTransition = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width / 2, size.height / 2) - strokeWidth / 2;
    
    if (progress <= 0) return;

    // Create shadow paint for glow effect
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3);
    
    // Calculate the angle for this progress
    final sweepAngle = (progress / 100) * 2 * math.pi;
    
    // Create smooth gradient paint
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    
    // If smooth transition enabled, apply radial gradient 
    if (smoothTransition) {
      paint.shader = RadialGradient(
        colors: [
          color.withOpacity(0.9),
          color,
        ],
        stops: [0.0, 1.0],
        center: Alignment.center,
      ).createShader(Rect.fromCircle(
        center: center,
        radius: radius,
      ));
    } else {
      paint.color = color;
    }
    
    // Start angle (top of circle)
    double startAngle = -math.pi / 2;
    
    // Optional: Draw subtle shadow for depth
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + 1),
      startAngle,
      sweepAngle,
      false,
      shadowPaint,
    );
    
    // Draw the progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
           oldDelegate.strokeWidth != strokeWidth ||
           oldDelegate.color != color ||
           oldDelegate.smoothTransition != smoothTransition;
  }
}

// Lista di consigli virali da mostrare nel container inferiore
const List<String> viralTips = [
  "Scheduling posts at optimal times can increase engagement by up to 40%!",
  "Posts published between 9-11 AM and 7-9 PM typically get the most views.",
  "Consistency is key - posting regularly helps build audience trust.",
  "Use platform-specific hashtags to reach your target audience effectively.",
  "Cross-platform scheduling saves time and ensures consistent messaging.",
  "The best time to post varies by platform - research your audience's habits!",
  "Scheduled posts allow you to maintain presence even when you're busy.",
  "Engage with your audience in the first hour after posting for maximum reach.",
  "Quality content + perfect timing = viral potential! 🚀",
  "Plan your content calendar ahead to maintain consistent posting schedule.",
];

/// PostSchedulerPage - Pagina per la programmazione di post su piattaforme social
/// 
/// OTTIMIZZAZIONI IMPLEMENTATE:
/// - Caricamento file su Cloudflare una sola volta per multiple piattaforme
/// - Caching degli URL Cloudflare per evitare upload duplicati
/// - Gestione ottimizzata per YouTube (non richiede Cloudflare)
/// - UI migliorata con indicatori di stato del caricamento
/// - Supporto per thumbnail automatici per video
/// 
/// FLUSSO OTTIMIZZATO:
/// 1. Se ci sono multiple piattaforme, il file viene caricato una volta su Cloudflare
/// 2. L'URL viene cached e riutilizzato per tutte le piattaforme
/// 3. YouTube usa direttamente il file locale (non ha bisogno di Cloudflare)
/// 4. Thumbnail generati automaticamente per video e cached
class PostSchedulerPage extends StatefulWidget {
  final File? videoFile;
  // Nuove liste per supportare più media (carosello / multi-media)
  final List<File>? mediaFiles;
  final List<bool>? isImageFiles;
  final String? title;
  final String? description;
  final Map<String, List<String>>? selectedAccounts;
  final Map<String, List<Map<String, dynamic>>>? socialAccounts;
  final DateTime? scheduledDateTime;
  final Map<String, Map<String, String>>? platformDescriptions;
  final String? cloudflareUrl;
  final bool? isPremium;
  final Function? onSchedulingComplete;
  final String platform;
  final String? draftId; // Add draftId
  final File? youtubeThumbnailFile; // Add thumbnail param
  final Map<String, Map<String, dynamic>>? youtubeOptions; // Opzioni YouTube per ogni account
  
  const PostSchedulerPage({
    Key? key, 
    this.videoFile,
    this.mediaFiles,
    this.isImageFiles,
    this.title,
    this.description,
    this.selectedAccounts,
    this.socialAccounts,
    this.scheduledDateTime,
    this.platformDescriptions,
    this.cloudflareUrl,
    this.isPremium,
    this.onSchedulingComplete,
    required this.platform,
    this.draftId, // Add draftId
    this.youtubeThumbnailFile, // Add thumbnail param
    this.youtubeOptions, // Opzioni YouTube per ogni account
  }) : super(key: key);

  @override
  _PostSchedulerPageState createState() => _PostSchedulerPageState();
}

class _PostSchedulerPageState extends State<PostSchedulerPage> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  DateTime _scheduledDate = DateTime.now().add(const Duration(hours: 1));
  File? _mediaFile;
  // Liste locali di media per supportare caroselli / multi-media
  List<File> _mediaFiles = [];
  List<bool> _isImageFiles = [];
  bool _isLoading = false;
  String? _errorMessage;
  final ImagePicker _picker = ImagePicker();
  
  // Social media accounts
  List<Map<String, dynamic>> _socialAccounts = [];
  String? _selectedAccountId;
  
  // Ottimizzazione caricamento Cloudflare - variabili per gestire il caricamento una sola volta
  String? _cachedCloudflareUrl; // URL Cloudflare del file caricato
  // Nuova lista per supportare più media (carosello Instagram)
  List<String> _cachedCloudflareUrls = [];
  String? _cachedThumbnailUrl; // URL Cloudflare del thumbnail caricato
  bool _isUploadingToCloudflare = false; // Flag per tracciare se è in corso un upload
  String _uploadStatus = ''; // Messaggio di stato per l'upload
  
  // Gestione scheduling multiple piattaforme
  Map<String, bool> _platformSchedulingStatus = {}; // Stato di scheduling per ogni piattaforma
  Map<String, String?> _platformErrors = {}; // Errori per ogni piattaforma
  bool _isMultiPlatformScheduling = false; // Flag per indicare se stiamo schedulando multiple piattaforme
  int _completedPlatforms = 0; // Contatore piattaforme completate
  int _totalPlatforms = 0; // Totale piattaforme da schedulare
  
  // Progress tracking per il cerchio di progresso
  double _schedulingProgress = 0.0;
  String _schedulingStatus = 'Preparing scheduling...';
  
  // Variabili per la gestione dei crediti (solo per YouTube)
  bool _isPremium = false;
  int _currentCredits = 0;
  int _creditsDeducted = 0;
  
  // Timer for auto-rotating tips
  Timer? _tipsTimer;
  // Current tip index
  int _currentTipIndex = 0;
  // To track if tips section is expanded or collapsed
  bool _isTipsExpanded = true;
  // Animation controllers for tips section
  late AnimationController _tipsAnimController;
  late Animation<double> _tipsHeightAnimation;
  late Animation<double> _tipsOpacityAnimation;
  
  // Platform colors for UI display
  final Map<String, Color> _platformColors = {
    'TikTok': const Color(0xFFC974E8),
    'YouTube': const Color(0xFFE57373),
    'Facebook': const Color(0xFF64B5F6),
    'Twitter': const Color(0xFF4FC3F7),
    'Threads': const Color(0xFFF7C167),
    'Instagram': const Color(0xFFE040FB),
    'file_structuring': const Color(0xFF6C63FF),
  };
  
  // Platform-specific URLs
  final String _twitterWorkerUrl = 'https://twitterscheduler.giuseppemaria162.workers.dev/api/schedule';
  // IMPORTANTE: NON USARE LA ROOT URL, usare SEMPRE /api/schedule per Instagram
  final String _instagramWorkerUrl = 'https://instagramscheduler.giuseppemaria162.workers.dev/api/schedule';
  // IMPORTANTE: NON USARE LA ROOT URL, usare SEMPRE /api/schedule per Facebook
  final String _facebookWorkerUrl = 'https://facebookscheduler.giuseppemaria162.workers.dev/api/schedule';
  // IMPORTANTE: NON USARE LA ROOT URL, usare SEMPRE /api/schedule per Threads
  final String _threadsWorkerUrl = 'https://threadsscheduler.giuseppemaria162.workers.dev/api/schedule';
  // IMPORTANTE: NON USARE LA ROOT URL, usare SEMPRE /api/schedule per TikTok
  final String _tiktokWorkerUrl = 'https://tiktokscheduler.giuseppemaria162.workers.dev/api/schedule';
  
  // GoogleSignIn per YouTube
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/youtube.upload',
      'https://www.googleapis.com/auth/youtube.readonly',
      'https://www.googleapis.com/auth/youtube',
      'https://www.googleapis.com/auth/youtube.force-ssl'
    ],
    clientId: '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com',
  );
  
  String? _draftId;
  
  @override
  void initState() {
    super.initState();
    _draftId = widget.draftId;
    
    // Tips animation controller
    _tipsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    _tipsHeightAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _tipsAnimController,
      curve: Curves.easeInOut,
    ));
    
    _tipsOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _tipsAnimController,
      curve: Curves.easeIn,
    ));
    
    // Set initial state
    if (_isTipsExpanded) {
      _tipsAnimController.value = 1.0;
    }
    
    // Start the tips timer to auto-rotate tips every 10 seconds
    _startTipsTimer();
    
    // Initialize with values provided by widget
    if (widget.title != null) {
      _textController.text = widget.title!;
    }
    
    // Inizializza le liste di media (singolo file o carosello)
    if (widget.mediaFiles != null && widget.mediaFiles!.isNotEmpty) {
      _mediaFiles = List<File>.from(widget.mediaFiles!);
      if (widget.isImageFiles != null && widget.isImageFiles!.isNotEmpty) {
        _isImageFiles = List<bool>.from(widget.isImageFiles!);
      } else {
        // Se non vengono passati i flag, deducili dall'estensione del file
        _isImageFiles = _mediaFiles
            .map((f) => _determineMediaTypeFromFile(f) == 'image')
            .toList();
      }
      // Usa il primo media come file principale legacy
      _mediaFile = _mediaFiles.first;
    } else if (widget.videoFile != null) {
      // Retrocompatibilità: usa il singolo file
      _mediaFile = widget.videoFile;
      _mediaFiles = [widget.videoFile!];
      _isImageFiles = [_determineMediaTypeFromFile(widget.videoFile!) == 'image'];
    }
    
    // If description is provided but no title, use description as text
    if (widget.description != null && (widget.title == null || widget.title!.isEmpty)) {
      _textController.text = widget.description!;
    }
    
    // Use scheduled date if provided
    if (widget.scheduledDateTime != null) {
      _scheduledDate = widget.scheduledDateTime!;
    }
    
    // Load social media accounts based on platform
    _loadSocialAccounts();
    
    // Controlla lo status premium dell'utente (solo per YouTube)
      _checkUserPremiumStatus();
  }
  
  @override
  void dispose() {
    _textController.dispose();
    _tipsTimer?.cancel();
    _tipsAnimController.dispose();
    super.dispose();
  }
  
  void _startTipsTimer() {
    _tipsTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (mounted && _isTipsExpanded) {
        setState(() {
          _currentTipIndex = (_currentTipIndex + 1) % viralTips.length;
        });
      }
    });
  }

  // Move to next tip
  void _nextTip() {
    if (!_isTipsExpanded) return;
    
    setState(() {
      _currentTipIndex = (_currentTipIndex + 1) % viralTips.length;
    });
    
    // Reset the timer when manually changing tip
    _tipsTimer?.cancel();
    _startTipsTimer();
  }

  // Toggle tips section visibility
  void _toggleTipsVisibility() {
    setState(() {
      _isTipsExpanded = !_isTipsExpanded;
      if (_isTipsExpanded) {
        _tipsAnimController.forward();
      } else {
        _tipsAnimController.reverse();
      }
    });
  }
  
  // Return different colors for different tips to add visual variety
  Color _getTipColor(int index) {
    final colors = [
      const Color(0xFFC974E8), // Purple
      const Color(0xFFF7C167), // Orange
      const Color(0xFF67E4C8), // Teal
    ];
    
    return colors[index % colors.length];
  }
  
  // Metodo per aggiornare il progresso dello scheduling
  void _updateSchedulingProgress(double progress, String status) {
    setState(() {
      _schedulingProgress = progress;
      _schedulingStatus = status;
    });
  }
  
  // Metodo per calcolare i crediti sottratti (solo per YouTube)
  int _calculateCreditsDeducted() {
    try {
      // Calcola la dimensione del file in megabyte
      final fileSizeBytes = _mediaFile?.lengthSync() ?? 0;
      final fileSizeMB = fileSizeBytes / (1024 * 1024);
      
      // Moltiplica per 0.40 e arrotonda per eccesso
      final creditsToDeduct = (fileSizeMB * 0.40).ceil();
      
      return creditsToDeduct;
    } catch (e) {
      print('Errore nel calcolo dei crediti: $e');
      return 1; // Valore di default in caso di errore
    }
  }
  
  // Metodo per verificare se l'utente è premium e ottenere i crediti attuali
  Future<void> _checkUserPremiumStatus() async {
    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final userSnapshot = await FirebaseDatabase.instance.ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .get();

      if (userSnapshot.exists) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _isPremium = userData['isPremium'] == true;
          _currentCredits = userData['credits'] ?? 0;
        });
      }
    } catch (e) {
      print('Errore nel controllo dello status premium: $e');
    }
  }
  
  // Metodo per aggiornare i crediti dell'utente nel database
  Future<void> _updateUserCredits() async {
    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Calcola i nuovi crediti
      final newCredits = _currentCredits - _creditsDeducted;
      
      // Aggiorna i crediti nel database con il path corretto
      await FirebaseDatabase.instance.ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .update({
        'credits': newCredits,
      });
      
      print('Crediti aggiornati: $_currentCredits -> $newCredits (sottratti: $_creditsDeducted)');
    } catch (e) {
      print('Errore nell\'aggiornamento dei crediti: $e');
    }
  }
  
  // Metodo per mostrare il popup di successo con i crediti sottratti (solo per YouTube)
  void _showYouTubeSuccessDialog() {
    if (_isPremium) {
      // Per utenti premium, naviga direttamente indietro
      Navigator.pop(context, true);
      return;
    }
    // Per utenti non premium, mostra direttamente il dialog generico
    _showSuccessDialog();
  }
  
  // Metodo per mostrare il popup di successo minimal e professionale
  void _showSuccessDialog() {
    // Verifica che il context sia ancora valido
    if (!mounted) {
      print('Widget not mounted, cannot show success dialog');
      return;
    }

    // Calcola i crediti sottratti per tutte le piattaforme se non premium
    if (!_isPremium) {
    _creditsDeducted = _calculateCreditsDeducted();
    }
    
    // Aggiungi un piccolo delay per assicurarsi che il rendering sia completato
    Future.delayed(Duration(milliseconds: 100), () {
      if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 400, // Come il partial success dialog
              minWidth: 0,
            ),
            child: Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header con icona di successo
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF667eea).withOpacity(0.1),
                          Color(0xFF764ba2).withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Icona di successo con animazione
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF667eea),
                                Color(0xFF764ba2),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              transform: GradientRotation(135 * 3.14159 / 180),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF667eea).withOpacity(0.3),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Post Scheduled Successfully!',
                          style: TextStyle(
                            color: Color(0xFF2C2C3E),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Your content has been scheduled for publication',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  
                  // Contenuto principale
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      children: [
                        // Dettagli dello scheduling
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.grey[200]!,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header sezione dettagli
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule,
                                    color: Color(0xFF667eea),
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Scheduling Details',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF2C2C3E),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              
                              // Data e ora
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.grey[200]!,
                                          width: 1,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Publication Date',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            DateFormat('MMM d, y').format(_scheduledDate),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF2C2C3E),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Container(
                                      padding: EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.grey[200]!,
                                          width: 1,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Publication Time',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            DateFormat('HH:mm').format(_scheduledDate),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF2C2C3E),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                            ],
                          ),
                        ),
                        
                        SizedBox(height: 12),
                        
                        // Pulsante per andare ai post schedulati
                        Container(
                          width: double.infinity,
                          height: 38,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF667eea),
                                Color(0xFF764ba2),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              transform: GradientRotation(135 * 3.14159 / 180),
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF667eea).withOpacity(0.3),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () async {
                                // Se non premium, aggiorna i crediti
                                if (!_isPremium) {
                                  await _updateUserCredits();
                                }
                                Navigator.of(context).pop(); // Chiudi il dialog
                                // Naviga alla pagina dei post schedulati con la data specifica
                                Navigator.of(context).pushNamed(
                                  '/scheduled-posts',
                                  arguments: {
                                    'selectedDate': _scheduledDate,
                                    'scrollToTime': true,
                                  },
                                );
                              },
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.calendar_today,
                                      color: Colors.white,
                                      size: 15,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'View Scheduled Posts',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                        // Pulsante secondario per continuare
                        Container(
                          width: double.infinity,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () async {
                                // Se non premium, aggiorna i crediti
                                if (!_isPremium) {
                                  await _updateUserCredits();
                                }
                                Navigator.of(context).pop(); // Chiudi il dialog
                                Navigator.pushNamedAndRemoveUntil(
                                  context, 
                                  '/', 
                                  (route) => false
                                );
                              },
                              child: Center(
                                child: Text(
                                  'Continue',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  });
  }
  
  // Metodo per caricare gli account social per la piattaforma specifica
  Future<void> _loadSocialAccounts() async {
    try {
      print('Loading social accounts for platform: ${widget.platform}');
      
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('User not authenticated');
        return;
      }
      
      // Determina il percorso del database in base alla piattaforma
      String databasePath;
      switch (widget.platform) {
        case 'Instagram':
          databasePath = 'users/${currentUser.uid}/instagram';
          break;
        case 'Facebook':
          databasePath = 'users/${currentUser.uid}/facebook';
          break;
        case 'Threads':
          databasePath = 'users/users/${currentUser.uid}/social_accounts/threads';
          break;
        case 'TikTok':
          databasePath = 'users/${currentUser.uid}/tiktok';
          break;
        case 'YouTube':
          databasePath = 'users/${currentUser.uid}/youtube';
          break;
        default:
          databasePath = 'users/users/${currentUser.uid}/social_accounts/${widget.platform.toLowerCase()}';
      }
      
      print('Loading accounts from database path: $databasePath');
      
      final accountSnapshot = await FirebaseDatabase.instance
          .ref()
          .child(databasePath)
          .get();
      
      if (!accountSnapshot.exists) {
        print('No accounts found for platform: ${widget.platform}');
        setState(() {
          _socialAccounts = [];
        });
        return;
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final List<Map<String, dynamic>> accounts = [];
      
      // Gestisci struttura annidata o piatta
      if (accountData is Map) {
        accountData.forEach((key, value) {
          if (value is Map) {
            final account = Map<String, dynamic>.from(value);
            account['id'] = key.toString();
            accounts.add(account);
          }
        });
      }
      
      print('Loaded ${accounts.length} accounts for ${widget.platform}');
      
      setState(() {
        _socialAccounts = accounts;
        // Se c'è un account selezionato dal widget, usalo
        if (widget.selectedAccounts != null && 
            widget.selectedAccounts!.containsKey(widget.platform) && 
            widget.selectedAccounts![widget.platform]!.isNotEmpty) {
          _selectedAccountId = widget.selectedAccounts![widget.platform]![0];
        } else if (accounts.isNotEmpty) {
          // Altrimenti seleziona il primo account disponibile
          _selectedAccountId = accounts[0]['id'];
        }
      });
      
      // Se abbiamo account e siamo in modalità multi-piattaforma, avvia lo scheduling
      if (widget.selectedAccounts != null && widget.selectedAccounts!.isNotEmpty) {
        print('Multiple platforms detected, starting optimized scheduling');
        await _scheduleAllPlatforms();
      } else if (accounts.isNotEmpty && _selectedAccountId != null) {
        // Se abbiamo un account selezionato ma non siamo in modalità multi-piattaforma,
        // non avviamo automaticamente lo scheduling - l'utente dovrà premere il pulsante
        print('Single platform with account selected, waiting for user action');
      } else {
        print('No accounts available or selected');
      }
      
    } catch (e) {
      print('Error loading social accounts: $e');
      setState(() {
        _errorMessage = 'Unable to load your social accounts. Please try again.';
      });
    }
  }
  
  // Metodo per caricare il file su Cloudflare una sola volta e cachearlo
  Future<String?> _uploadFileToCloudflareOnce() async {
    // Se abbiamo già un URL Cloudflare cached, lo restituiamo
    if (_cachedCloudflareUrl != null) {
      print('Using cached Cloudflare URL: $_cachedCloudflareUrl');
      return _cachedCloudflareUrl;
    }
    
    // Se abbiamo già un URL Cloudflare fornito dal widget, lo usiamo e lo cacheiamo
    if (widget.cloudflareUrl != null) {
      print('Using provided Cloudflare URL and caching it: ${widget.cloudflareUrl}');
      _cachedCloudflareUrl = widget.cloudflareUrl;
      return _cachedCloudflareUrl;
    }
    
    // Se non abbiamo un file da caricare, restituiamo null
    if (_mediaFile == null && _mediaFiles.isEmpty) {
      print('No media file to upload');
      return null;
    }
    
    // Se è già in corso un upload, aspettiamo con timeout
    if (_isUploadingToCloudflare) {
      print('Upload already in progress, waiting...');
      int waitCount = 0;
      while (_isUploadingToCloudflare && waitCount < 60) { // Max 30 secondi di attesa
        await Future.delayed(Duration(milliseconds: 500));
        waitCount++;
      }
      
      if (_isUploadingToCloudflare) {
        throw Exception('Upload timeout - upload is taking too long');
      }
      
      return _cachedCloudflareUrl;
    }
    
    // Iniziamo l'upload
    setState(() {
      _isUploadingToCloudflare = true;
      _uploadStatus = 'File scheduling...';
    });
    
    try {
      final File fileToUpload = _mediaFile ?? _mediaFiles.first;
      print('Starting single upload to Cloudflare R2: ${fileToUpload.path}');
      
      // Aggiorna il progresso per il caricamento
      _updateSchedulingProgress(65.0, 'File scheduling...');
      
      // Carica il file su Cloudflare con timeout
      final cloudflareUrl = await _uploadMediaToCloudflareR2(
        fileToUpload, 
        _getContentType(fileToUpload.path.split('.').last)
      ).timeout(
        Duration(minutes: 5),
        onTimeout: () {
          throw Exception('Upload to Cloudflare timed out');
        },
      );
      
      // Cachea l'URL
      _cachedCloudflareUrl = cloudflareUrl;
      _cachedCloudflareUrls = [cloudflareUrl];
      
      // Se è un video, genera e carica anche il thumbnail
      final mediaType = _determineMediaType(cloudflareUrl);
      if (mediaType == 'video') {
        _updateSchedulingProgress(68.0, 'Generating thumbnail...');
        
        try {
          final thumbnailUrl = await _generateThumbnail(_mediaFile).timeout(
            Duration(minutes: 2),
            onTimeout: () {
              print('Thumbnail generation timed out, continuing without thumbnail');
              return null;
            },
          );
          if (thumbnailUrl != null) {
            _cachedThumbnailUrl = thumbnailUrl;
            print('Thumbnail cached: $_cachedThumbnailUrl');
          }
        } catch (e) {
          print('Error generating thumbnail: $e, continuing without thumbnail');
        }
      } else if (mediaType == 'image') {
        // Per le immagini, usa direttamente la stessa URL come "thumbnail"
        _cachedThumbnailUrl = _cachedCloudflareUrl;
        print('Thumbnail for image set to media URL (no separate generation).');
      }
      
      _updateSchedulingProgress(70.0, 'File uploaded successfully!');
      
      setState(() {
        _uploadStatus = 'File uploaded successfully!';
      });
      
      print('File uploaded and cached successfully: $_cachedCloudflareUrl');
      return _cachedCloudflareUrl;
      
    } catch (e) {
      print('Error uploading file to Cloudflare: $e');
      setState(() {
        _uploadStatus = 'Upload error: $e';
      });
      throw e;
    } finally {
      setState(() {
        _isUploadingToCloudflare = false;
      });
    }
  }
  
  // Metodo per ottenere l'URL del thumbnail cached
  String? _getCachedThumbnailUrl() {
    return _cachedThumbnailUrl;
  }
  
  // Metodo per verificare se ci sono multiple piattaforme selezionate
  bool _hasMultiplePlatforms() {
    return widget.selectedAccounts != null && widget.selectedAccounts!.length > 1;
  }
  
  // Metodo per ottenere la lista delle piattaforme che richiedono Cloudflare
  List<String> _getPlatformsRequiringCloudflare() {
    if (widget.selectedAccounts == null) return [];
    
    // Ora tutte le piattaforme (incluso YouTube) hanno bisogno di Cloudflare per coerenza
    return widget.selectedAccounts!.keys.toList();
  }
  
  // Metodo per preparare il caricamento ottimizzato per multiple piattaforme
  Future<void> _prepareOptimizedUpload() async {
    if (!_hasMultiplePlatforms()) {
      print('Single platform selected, no optimization needed');
      return;
    }
    
    final platformsRequiringCloudflare = _getPlatformsRequiringCloudflare();
    if (platformsRequiringCloudflare.isEmpty) {
      print('No platforms require Cloudflare upload');
      return;
    }
    
    print('Multiple platforms detected: ${platformsRequiringCloudflare.join(', ')}');
    print('Preparing optimized upload for all platforms...');
    
    // Carica il file o i file (in caso di carosello) una sola volta per tutte le piattaforme
    if (_mediaFiles.isNotEmpty || _mediaFile != null || widget.cloudflareUrl != null) {
      // Per ora ottimizziamo l'upload principale; i media extra verranno gestiti
      // solo dove servono (es. carosello Instagram)
      await _uploadFileToCloudflareOnce();
      print('File uploaded once and cached for all platforms');
    }
  }
  
  // Metodo per schedulare tutte le piattaforme selezionate
  Future<void> _scheduleAllPlatforms() async {
    if (widget.selectedAccounts == null || widget.selectedAccounts!.isEmpty) {
      print('No platforms selected for scheduling');
      return;
    }
    
    setState(() {
      _isMultiPlatformScheduling = true;
      _completedPlatforms = 0;
      _totalPlatforms = widget.selectedAccounts!.length;
      _platformSchedulingStatus.clear();
      _platformErrors.clear();
      _isLoading = true;
      _errorMessage = null;
      _schedulingProgress = 0.0;
      _schedulingStatus = 'Preparing scheduling...';
    });
    
    print('Starting multi-platform scheduling for $_totalPlatforms platforms');
    
    // GENERA L'ID UNA SOLA VOLTA per tutto il processo
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }
    
    final String globalUniquePostId = _generateUniquePostId(currentUser.uid, 'multi_platform');
    print('🔄 [GLOBAL_ID] ID univoco generato una volta per tutto il processo: $globalUniquePostId');
    
    // Inizializza lo stato per tutte le piattaforme
    for (String platform in widget.selectedAccounts!.keys) {
      _platformSchedulingStatus[platform] = false;
      _platformErrors[platform] = null;
    }
    
    // Map per raccogliere i risultati di tutti gli account
    Map<String, Map<String, dynamic>> accountResults = {};
    
    try {
      // Fase 1: Preparazione (10%)
      _updateSchedulingProgress(10.0, 'Preparing platforms...');
      await Future.delayed(Duration(milliseconds: 500));
      
      // Prepara il caricamento ottimizzato se necessario
      if (_hasMultiplePlatforms()) {
        _updateSchedulingProgress(20.0, 'Optimizing file upload...');
        print('Preparing optimized upload for multiple platforms');
        await _prepareOptimizedUpload();
        _updateSchedulingProgress(30.0, 'File uploaded successfully');
      }
      
      // Fase 2: Scheduling delle piattaforme (30% - 90%)
      List<Future<void>> schedulingTasks = [];
      
              for (String platform in widget.selectedAccounts!.keys) {
          final accounts = widget.selectedAccounts![platform]!;
        for (final accountId in accounts) {
          schedulingTasks.add(_scheduleSinglePlatformWithResult(platform, accountId, accountResults, globalUniquePostId));
          }
        }
      
      // Calcola il progresso per ogni piattaforma completata
      double progressPerPlatform = 60.0 / _totalPlatforms; // 60% diviso per il numero di piattaforme
      
      // Esegui tutti gli scheduling in parallelo con timeout
      await Future.wait(schedulingTasks).timeout(
        Duration(minutes: 5),
        onTimeout: () {
          throw Exception('Scheduling timeout - some platforms may not have completed');
        },
      );
      
      // Fase 3: Salvataggio su Firebase (85% - 90%)
      _updateSchedulingProgress(85.0, 'Saving to database...');
      
      // Salva un solo record con tutti i risultati degli account
      if (accountResults.isNotEmpty) {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          // Determina testo da usare
          String postText = "";
          if (widget.title != null && widget.title!.isNotEmpty) {
            postText = widget.title!;
          } else if (_textController.text.isNotEmpty) {
            postText = _textController.text;
          } else if (widget.description != null && widget.description!.isNotEmpty) {
            postText = widget.description!;
          }
          // Per Instagram, TikTok, Facebook, Threads, Twitter il testo può essere vuoto/null
          if (["Instagram", "TikTok", "Facebook", "Threads", "Twitter"].contains(widget.platform) && (postText == null || postText.isEmpty)) {
            postText = "";
          }
          
          // Ottieni URL media se disponibile
          String? mediaUrl;
          String? thumbnailUrl;
          String mediaType = 'text';
          
          // 1) Prova a leggere dai risultati raccolti (caso singolo Instagram compreso)
          try {
            final firstResult = accountResults.values.firstWhere((r) => r['mediaUrl'] != null, orElse: () => {});
            if (firstResult.isNotEmpty) {
              mediaUrl = firstResult['mediaUrl'] as String?;
              thumbnailUrl = (firstResult['thumbnailUrl'] as String?) ?? (firstResult['cloudflareUrl'] as String?);
              mediaType = (firstResult['mediaType'] as String?) ?? (mediaUrl != null ? _determineMediaType(mediaUrl) : 'text');
            }
          } catch (_) {}
          
          // 2) Fallback sui valori globali se non disponibili dai risultati
          if (mediaUrl == null && (_mediaFile != null || widget.cloudflareUrl != null)) {
            mediaUrl = _cachedCloudflareUrl ?? widget.cloudflareUrl;
            mediaType = _determineMediaType(mediaUrl);
            thumbnailUrl = _getCachedThumbnailUrl();
          }
          // 3) Se ancora manca la thumbnail per immagini, usa mediaUrl
          if (thumbnailUrl == null && mediaUrl != null && mediaType == 'image') {
            thumbnailUrl = mediaUrl;
          }
          
          // Usa l'ID globale già generato
          print('🔄 [MULTI_PLATFORM] Usando ID univoco globale: $globalUniquePostId');
          
          // Ottieni durata del video se disponibile
          Map<String, int>? videoDuration;
          if (widget.videoFile != null) {
            videoDuration = await _getVideoDuration();
            if (videoDuration != null) {
              print('📋 [MULTI_PLATFORM] Video duration obtained: ${videoDuration['total_seconds']} seconds');
            }
          }
          
          // Ottieni lista di media URLs se disponibile (per caroselli)
          List<String>? mediaUrls;
          if (_cachedCloudflareUrls.isNotEmpty) {
            mediaUrls = _cachedCloudflareUrls;
            print('📸 [MULTI_PLATFORM] Media URLs disponibili: ${mediaUrls.length}');
          }
          
          await _saveMultiPlatformPostToFirebase(
            currentUser.uid,
            postText,
            _scheduledDate,
            mediaUrl,
            mediaType,
            thumbnailUrl,
            accountResults,
            globalUniquePostId, // Usa l'ID globale
            videoDuration, // Aggiungi durata del video
            mediaUrls, // Aggiungi lista di media URLs per caroselli
          );
        }
      }
      
      // Fase 4: Completamento (90% - 100%)
      _updateSchedulingProgress(90.0, 'Finalizing scheduling...');
      await Future.delayed(Duration(milliseconds: 500));
      _updateSchedulingProgress(100.0, 'Scheduling completed successfully!');
      
      print('All platforms scheduled successfully');
      
      // Verifica se tutte le piattaforme sono state completate
      bool allCompleted = _platformSchedulingStatus.values.every((status) => status);
      
      if (allCompleted) {
        // Mostra il popup di successo per scheduling multi-piattaforma completato
        _onSchedulingSuccess();
        _showSuccessDialog();
      } else {
        _showMultiPlatformPartialSuccessDialog();
      }
      
    } catch (e) {
      print('Error in multi-platform scheduling: $e');
      setState(() {
        _errorMessage = 'Unable to schedule your posts. Please try again.';
        _schedulingStatus = 'Scheduling failed';
      });
      _showMultiPlatformErrorDialog('Scheduling failed. Please try again.');
    } finally {
      setState(() {
        _isMultiPlatformScheduling = false;
        _isLoading = false;
      });
    }
  }
  
  // Metodo per schedulare una singola piattaforma
  Future<void> _scheduleSinglePlatform(String platform, String accountId, String uniquePostId) async {
    try {
      print('Scheduling $platform with account $accountId');
      
      setState(() {
        _platformSchedulingStatus[platform] = false;
        _platformErrors[platform] = null;
      });
      
      // Aggiorna il progresso per questa piattaforma
      double currentProgress = 30.0 + (_completedPlatforms * (60.0 / _totalPlatforms));
      _updateSchedulingProgress(currentProgress, 'Scheduling $platform...');
      
      // Usa la logica esistente per schedulare la piattaforma specifica
      await _schedulePlatformSpecific(platform, accountId, uniquePostId).timeout(
        Duration(minutes: 3),
        onTimeout: () {
          throw Exception('Timeout scheduling $platform');
        },
      );
      
      setState(() {
        _platformSchedulingStatus[platform] = true;
        _completedPlatforms++;
      });
      
      // Aggiorna il progresso dopo il completamento
      double newProgress = 30.0 + (_completedPlatforms * (60.0 / _totalPlatforms));
      _updateSchedulingProgress(newProgress, '$platform scheduled successfully');
      
      print('$platform scheduled successfully');
      
    } catch (e) {
      print('Error scheduling $platform: $e');
      setState(() {
        _platformErrors[platform] = e.toString();
        _completedPlatforms++;
      });
      
      // Aggiorna il progresso anche in caso di errore
      double newProgress = 30.0 + (_completedPlatforms * (60.0 / _totalPlatforms));
      _updateSchedulingProgress(newProgress, 'Error in $platform, continuing...');
      
      // Non rilanciare l'errore per permettere alle altre piattaforme di continuare
      // L'errore verrà gestito nel metodo chiamante
    }
  }
  
  // Nuovo metodo per schedulare una singola piattaforma e raccogliere i risultati
  Future<void> _scheduleSinglePlatformWithResult(String platform, String accountId, Map<String, Map<String, dynamic>> accountResults, String globalUniquePostId) async {
    try {
      print('Scheduling $platform with account $accountId and collecting results');
      
      setState(() {
        _platformSchedulingStatus[platform] = false;
        _platformErrors[platform] = null;
      });
      
      // Aggiorna il progresso per questa piattaforma
      double currentProgress = 30.0 + (_completedPlatforms * (60.0 / _totalPlatforms));
      _updateSchedulingProgress(currentProgress, 'Scheduling $platform...');
      
      // Usa la logica esistente per schedulare la piattaforma specifica e raccogliere i risultati
      final result = await _schedulePlatformSpecificWithResult(platform, accountId, globalUniquePostId).timeout(
        Duration(minutes: 3),
        onTimeout: () {
          throw Exception('Timeout scheduling $platform');
        },
      );
      
      // Salva il risultato nella map usando una chiave unica per account
      if (result != null) {
        final uniqueKey = '${platform}_${accountId}';
        accountResults[uniqueKey] = result;
      }
      
      setState(() {
        _platformSchedulingStatus[platform] = true;
        _completedPlatforms++;
      });
      
      // Aggiorna il progresso dopo il completamento
      double newProgress = 30.0 + (_completedPlatforms * (60.0 / _totalPlatforms));
      _updateSchedulingProgress(newProgress, '$platform scheduled successfully');
      
      print('$platform scheduled successfully with result collected');
      
    } catch (e) {
      print('Error scheduling $platform: $e');
      setState(() {
        _platformErrors[platform] = e.toString();
        _completedPlatforms++;
      });
      
      // Aggiorna il progresso anche in caso di errore
      double newProgress = 30.0 + (_completedPlatforms * (60.0 / _totalPlatforms));
      _updateSchedulingProgress(newProgress, 'Error in $platform, continuing...');
      
      // Non rilanciare l'errore per permettere alle altre piattaforme di continuare
      // L'errore verrà gestito nel metodo chiamante
    }
  }
  
  // Metodo per schedulare una piattaforma specifica
  Future<void> _schedulePlatformSpecific(String platform, String accountId, String uniquePostId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }
    
    // Gestione specifica per YouTube
    if (platform == 'YouTube') {
      await _scheduleYouTubePost(currentUser, uniquePostId);
      return;
    }
    
    // Per le altre piattaforme, usa la logica worker esistente
    await _scheduleWorkerBasedPlatform(platform, accountId, currentUser, uniquePostId);
  }
  
  // Nuovo metodo per schedulare una piattaforma specifica e restituire i risultati
  Future<Map<String, dynamic>?> _schedulePlatformSpecificWithResult(String platform, String accountId, String globalUniquePostId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }
    
    // Gestione specifica per YouTube
    if (platform == 'YouTube') {
      return await _scheduleYouTubePostWithResult(currentUser, globalUniquePostId);
    }
    
    // Per le altre piattaforme, usa la logica worker esistente
    return await _scheduleWorkerBasedPlatformWithResult(platform, accountId, currentUser, globalUniquePostId);
  }
  
  // Metodo per schedulare piattaforme basate su worker
  Future<void> _scheduleWorkerBasedPlatform(String platform, String accountId, User currentUser, [String? uniquePostId]) async {
    // Verifica connessione worker
    final workerUrl = _getWorkerUrlForPlatform(platform);
    final isWorkerReachable = await _checkWorkerConnection(workerUrl);
    if (!isWorkerReachable) {
      throw Exception('$platform scheduler worker is not reachable');
    }
    // Ottieni dati account
    final accountData = await _getAccountDataForPlatform(platform, accountId, currentUser);
    // Prepara dati per lo scheduling
    final schedulerData = await _prepareSchedulerData(platform, accountId, accountData, currentUser, uniquePostId!);
    // --- MODIFICA: inserisci le credenziali corrette per ogni account selezionato ---
    // Se la piattaforma NON è YouTube e ci sono più account selezionati per la stessa piattaforma,
    // invia una richiesta per ogni account, ognuna con le sue credenziali
    if (platform != 'YouTube' && widget.selectedAccounts != null && widget.selectedAccounts![platform] != null && widget.selectedAccounts![platform]!.length > 1) {
      for (final accId in widget.selectedAccounts![platform]!) {
        final accData = await _getAccountDataForPlatform(platform, accId, currentUser);
        final dataPerAccount = Map<String, dynamic>.from(schedulerData);
        dataPerAccount['accountId'] = accId;
        dataPerAccount['account_id'] = accId;
        dataPerAccount['oauth'] = _prepareOAuthData(accData, platform);
        dataPerAccount['username'] = _getUsernameForPlatform(platform, accData);
        dataPerAccount['account_username'] = _getUsernameForPlatform(platform, accData);
        dataPerAccount['profileImageUrl'] = _getProfileImageUrlForPlatform(platform, accData);
        dataPerAccount['account_profile_image_url'] = _getProfileImageUrlForPlatform(platform, accData);
        dataPerAccount['account_display_name'] = _getDisplayNameForPlatform(platform, accData);
        // LOG DETTAGLIATO
        print('==== POST REQUEST for $platform/$accId ====');
        print('accountId: ${dataPerAccount['accountId']}');
        print('account_id: ${dataPerAccount['account_id']}');
        print('username: ${dataPerAccount['username']}');
        print('account_username: ${dataPerAccount['account_username']}');
        print('accessToken: ${dataPerAccount['oauth']['accessToken']}');
        print('userId: ${dataPerAccount['oauth']['userId']}');
        print('uniquePostId: ${dataPerAccount['uniquePostId']}');
        print('all_selected_accounts: ${jsonEncode(dataPerAccount['all_selected_accounts'])}');
        print('FULL PAYLOAD: ${jsonEncode(dataPerAccount)}');
        print('==========================================');
        // Invia la richiesta per ogni account
        final response = await http.post(
          Uri.parse(workerUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${await currentUser.getIdToken()}',
          },
          body: jsonEncode(dataPerAccount),
        ).timeout(Duration(seconds: 30));
        if (response.statusCode != 200) {
          final responseData = jsonDecode(response.body);
          throw Exception('Failed to schedule $platform post: ${responseData['error'] ?? 'Unknown error'}');
        }
        final responseData = jsonDecode(response.body);
        print('$platform post scheduled successfully, ID: ${responseData['id']}');
        // Salva su Firebase
        // Ottieni mediaUrls se disponibile (per caroselli)
        List<String>? mediaUrls;
        if (dataPerAccount['media_urls'] != null && dataPerAccount['media_urls'] is List) {
          mediaUrls = List<String>.from(dataPerAccount['media_urls']);
        } else if (_cachedCloudflareUrls.isNotEmpty) {
          mediaUrls = _cachedCloudflareUrls;
        }
        
        await _saveScheduledPostToFirebase(
          currentUser.uid,
          accId,
          dataPerAccount['text'],
          _scheduledDate,
          dataPerAccount['mediaUrl'],
          dataPerAccount['mediaType'],
          responseData['id'],
          platform,
          dataPerAccount['username'],
          dataPerAccount['account_display_name'],
          dataPerAccount['profileImageUrl'],
          dataPerAccount['thumbnailUrl'],
          dataPerAccount['uniquePostId'],
          dataPerAccount['videoDuration'],
          null,
          mediaUrls, // Aggiungi lista di media URLs per caroselli
        );
      }
      return;
    }
    // --- FINE MODIFICA ---
    // Caso standard (un solo account o YouTube)
    final response = await http.post(
      Uri.parse(workerUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await currentUser.getIdToken()}',
      },
      body: jsonEncode(schedulerData),
    ).timeout(Duration(seconds: 30));
    if (response.statusCode != 200) {
      final responseData = jsonDecode(response.body);
      throw Exception('Failed to schedule $platform post: ${responseData['error'] ?? 'Unknown error'}');
    }
    final responseData = jsonDecode(response.body);
    print('$platform post scheduled successfully, ID: ${responseData['id']}');
    // Salva su Firebase
    // Ottieni mediaUrls se disponibile (per caroselli)
    List<String>? mediaUrls;
    if (schedulerData['media_urls'] != null && schedulerData['media_urls'] is List) {
      mediaUrls = List<String>.from(schedulerData['media_urls']);
    } else if (_cachedCloudflareUrls.isNotEmpty) {
      mediaUrls = _cachedCloudflareUrls;
    }
    
    await _saveScheduledPostToFirebase(
      currentUser.uid,
      accountId,
      schedulerData['text'],
      _scheduledDate,
      schedulerData['mediaUrl'],
      schedulerData['mediaType'],
      responseData['id'],
      platform,
      _getUsernameForPlatform(platform, accountData),
      _getDisplayNameForPlatform(platform, accountData),
      _getProfileImageUrlForPlatform(platform, accountData),
      schedulerData['thumbnailUrl'],
      schedulerData['uniquePostId'],
      schedulerData['videoDuration'],
      null,
      mediaUrls, // Aggiungi lista di media URLs per caroselli
    );
  }
  
  // Nuovo metodo per schedulare piattaforme basate su worker e restituire i risultati
  Future<Map<String, dynamic>?> _scheduleWorkerBasedPlatformWithResult(String platform, String accountId, User currentUser, String globalUniquePostId) async {
    // Verifica connessione worker
    final workerUrl = _getWorkerUrlForPlatform(platform);
    final isWorkerReachable = await _checkWorkerConnection(workerUrl);
    
    if (!isWorkerReachable) {
      throw Exception('$platform scheduler worker is not reachable');
    }
    
    // Ottieni dati account
    final accountData = await _getAccountDataForPlatform(platform, accountId, currentUser);
    
    // Prepara dati per lo scheduling
    final schedulerData = await _prepareSchedulerData(platform, accountId, accountData, currentUser, globalUniquePostId);
    
    // Invia al worker
    final response = await http.post(
      Uri.parse(workerUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await currentUser.getIdToken()}',
      },
      body: jsonEncode(schedulerData),
    ).timeout(Duration(seconds: 30));
    
    if (response.statusCode != 200) {
      final responseData = jsonDecode(response.body);
      throw Exception('Failed to schedule $platform post: ${responseData['error'] ?? 'Unknown error'}');
    }
    
    final responseData = jsonDecode(response.body);
    print('$platform post scheduled successfully, ID: ${responseData['id']}');
    
    // Restituisci i risultati invece di salvare su Firebase, includendo media e thumbnail usati
    return {
      'platform': platform,
      'accountId': accountId,
      'workerId': responseData['id'],
      'accountUsername': _getUsernameForPlatform(platform, accountData),
      'accountDisplayName': _getDisplayNameForPlatform(platform, accountData),
      'accountProfileImageUrl': _getProfileImageUrlForPlatform(platform, accountData),
      // valori effettivi usati nel payload
      'mediaUrl': schedulerData['mediaUrl'],
      'mediaType': schedulerData['mediaType'],
      'thumbnailUrl': schedulerData['thumbnailUrl'],
    };
  }
  
  // Metodo helper per ottenere l'URL del worker per una piattaforma
  String _getWorkerUrlForPlatform(String platform) {
    switch (platform) {
      case 'Twitter':
        return _twitterWorkerUrl;
      case 'Instagram':
        return _instagramWorkerUrl;
      case 'Facebook':
        return _facebookWorkerUrl;
      case 'Threads':
        return _threadsWorkerUrl;
      case 'TikTok':
        return _tiktokWorkerUrl;
      default:
        throw Exception('Unsupported platform: $platform');
    }
  }
  
  // Metodo helper per ottenere i dati account per una piattaforma
  Future<Map<dynamic, dynamic>> _getAccountDataForPlatform(String platform, String accountId, User currentUser) async {
    String databasePath;
    
    switch (platform) {
      case 'Instagram':
        databasePath = 'users/${currentUser.uid}/instagram';
        break;
      case 'Facebook':
        databasePath = 'users/${currentUser.uid}/facebook';
        break;
      case 'Threads':
        databasePath = 'users/users/${currentUser.uid}/social_accounts/threads';
        break;
      case 'TikTok':
        databasePath = 'users/${currentUser.uid}/tiktok';
        break;
      case 'YouTube':
        databasePath = 'users/${currentUser.uid}/youtube';
        break;
      default:
        databasePath = 'users/users/${currentUser.uid}/social_accounts/${platform.toLowerCase()}';
    }
    
    final accountSnapshot = await FirebaseDatabase.instance
        .ref()
        .child(databasePath)
        .get();
    
    if (!accountSnapshot.exists) {
      throw Exception('$platform account not found');
    }
    
    final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
    
    // Gestisci struttura annidata
    if (accountData.containsKey(accountId)) {
      return accountData[accountId] as Map<dynamic, dynamic>;
    } else {
      // Per YouTube, se non trova l'accountId, potrebbe essere che i dati sono al livello root
      if (platform == 'YouTube' && accountData.containsKey('channel_id')) {
        return accountData;
      }
      return accountData;
    }
  }
  
  // Metodo helper per preparare i dati per lo scheduling
  Future<Map<String, dynamic>> _prepareSchedulerData(String platform, String accountId, Map<dynamic, dynamic> accountData, User currentUser, String uniquePostId) async {
    // LOG: Stato iniziale dei dati
    print('--- DEBUG SCHEDULER ---');
    print('selectedAccounts: ' + (widget.selectedAccounts?.toString() ?? 'null'));
    print('socialAccounts: ' + (widget.socialAccounts?.map((k,v) => MapEntry(k, v.map((a) => a['id']).toList())).toString() ?? 'null'));
    // Ottieni URL media se necessario
    String? mediaUrl;
    List<String> mediaUrls = [];
    String? thumbnailUrl;
    String mediaType = 'text';
    
    final bool hasMultipleMedia = _mediaFiles.length > 1;
    
    if (_mediaFile != null || widget.cloudflareUrl != null || _mediaFiles.isNotEmpty) {
      // Determine media type from the original file first
      if (_mediaFile != null) {
        mediaType = _determineMediaTypeFromFile(_mediaFile!);
      } else if (widget.cloudflareUrl != null) {
        mediaType = _determineMediaType(widget.cloudflareUrl);
      } else if (_mediaFiles.isNotEmpty) {
        mediaType = _determineMediaTypeFromFile(_mediaFiles.first);
      }
      
      // Gestione carosello Instagram: più media -> lista di URL (media_urls)
      if (platform == 'Instagram' && hasMultipleMedia && _mediaFiles.isNotEmpty) {
        print('📸 [INSTAGRAM] Preparing multiple media for Instagram carousel scheduling...');
        mediaUrls = [];
        final int maxItems = math.min(10, _mediaFiles.length);
        for (int i = 0; i < maxItems; i++) {
          final File file = _mediaFiles[i];
          final String ext = file.path.split('.').last;
          final bool isImage = _determineMediaTypeFromFile(file) == 'image';
          
          try {
            String? finalUrl;
            
            if (isImage) {
              // Resize image for Instagram aspect ratio, then upload
              print('📸 [INSTAGRAM] Resizing carousel image index=$i for Instagram...');
              final resizedImageFile = await _resizeImageForInstagram(file);
              if (resizedImageFile != null) {
                final resizedImageUrl = await _uploadResizedImageToCloudflare(resizedImageFile);
                if (resizedImageUrl != null) {
                  finalUrl = resizedImageUrl;
                  print('📸 [INSTAGRAM] Using resized image URL for carousel index=$i: $finalUrl');
                }
              }
            }
            
            // Se non siamo riusciti a fare il resize o non è un'immagine, usa l'upload standard
            if (finalUrl == null) {
              finalUrl = await _uploadMediaToCloudflareR2(
                file,
                _getContentType(ext),
              );
            }
            
            if (finalUrl != null) {
              mediaUrls.add(finalUrl);
            }
          } catch (error) {
            print('❌ [INSTAGRAM] Error processing carousel media index=$i: $error');
          }
        }
        
        if (mediaUrls.isNotEmpty) {
          // Prima URL usata come mediaUrl legacy
          mediaUrl = mediaUrls.first;
          _cachedCloudflareUrl = mediaUrl;
          _cachedCloudflareUrls = mediaUrls;
          print('📸 [INSTAGRAM] Carousel media URLs prepared: count=${mediaUrls.length}');
        } else {
          // Fallback: prova comunque l'upload singolo
          mediaUrl = await _uploadFileToCloudflareOnce();
        }
      } else {
        // Gestione standard (singolo media o piattaforme non-Instagram)
      // Special handling for Instagram images - resize to compatible aspect ratio
      if (platform == 'Instagram' && mediaType == 'image' && _mediaFile != null) {
        print('📸 [INSTAGRAM] Processing image for Instagram aspect ratio requirements...');
        
        try {
          // Resize the image for Instagram
          final resizedImageFile = await _resizeImageForInstagram(_mediaFile!);
          
          if (resizedImageFile != null) {
            // Upload the resized image to Cloudflare
            final resizedImageUrl = await _uploadResizedImageToCloudflare(resizedImageFile);
            
            if (resizedImageUrl != null) {
              // Use the resized image URL for Instagram
              mediaUrl = resizedImageUrl;
              print('📸 [INSTAGRAM] Using resized image URL for Instagram: $mediaUrl');
            } else {
              print('⚠️ [INSTAGRAM] Failed to upload resized image, using original URL');
              mediaUrl = await _uploadFileToCloudflareOnce();
            }
          } else {
            print('⚠️ [INSTAGRAM] Failed to resize image, using original URL');
            mediaUrl = await _uploadFileToCloudflareOnce();
          }
        } catch (error) {
          print('❌ [INSTAGRAM] Error processing image for Instagram: $error');
          // Continue with original URL if processing fails
          mediaUrl = await _uploadFileToCloudflareOnce();
        }
      } else {
        // For non-Instagram platforms or non-images, use original upload
        mediaUrl = await _uploadFileToCloudflareOnce();
        }
      }
      
      thumbnailUrl = _getCachedThumbnailUrl();
    }
    
    // Determina testo da usare
    String postText = "";
    
    // Usa descrizione specifica per piattaforma se disponibile
    if (widget.platformDescriptions != null && 
        widget.platformDescriptions!.containsKey(platform) && 
        widget.platformDescriptions![platform]!.containsKey(accountId)) {
      final platformSpecificText = widget.platformDescriptions![platform]![accountId];
      if (platformSpecificText != null && platformSpecificText.isNotEmpty) {
        postText = platformSpecificText;
      }
    } else {
      // Se non c'è descrizione specifica in platformDescriptions, 
      // significa che l'utente ha disabilitato il contenuto globale per questo account
      // Non fare fallback alla descrizione globale
      postText = "";
    }
    
    // Per Instagram, TikTok, Facebook, Threads, Twitter il testo può essere vuoto/null
    if (["Instagram", "TikTok", "Facebook", "Threads", "Twitter"].contains(platform) && (postText == null || postText.isEmpty)) {
      postText = "";
    }
    
    // Usa l'ID passato come parametro
    
    print('📋 [SCHEDULER_DATA] Preparazione dati per scheduling:');
    print('📋 [SCHEDULER_DATA] - Platform: $platform');
    print('📋 [SCHEDULER_DATA] - Account ID: $accountId');
    print('📋 [SCHEDULER_DATA] - User ID: ${currentUser.uid}');
    print('📋 [SCHEDULER_DATA] - Unique Post ID: $uniquePostId');
    
    // Prepara dati base
    final schedulerData = {
      'accountId': accountId,
      'text': postText,
      'description': postText, // duplicato come richiesto
      'scheduledTime': _scheduledDate.millisecondsSinceEpoch,
      'userId': currentUser.uid,
      'username': _getUsernameForPlatform(platform, accountData),
      'account_username': _getUsernameForPlatform(platform, accountData),
      'profileImageUrl': _getProfileImageUrlForPlatform(platform, accountData), // Aggiungo la profile_image_url
      'account_profile_image_url': _getProfileImageUrlForPlatform(platform, accountData),
      'account_display_name': _getDisplayNameForPlatform(platform, accountData),
      'account_id': accountId,
      'platform_info': '[$platform]', // racchiuso tra parentesi quadre
      'oauth': _prepareOAuthData(accountData, platform),
      'timeZone': DateTime.now().timeZoneName,
      'timeZoneOffset': DateTime.now().timeZoneOffset.inMinutes,
      'uniquePostId': uniquePostId, // Usa l'ID globale
    };
    
    // Aggiungi la lista di tutti i profili social selezionati SOLO per piattaforme diverse da Instagram
    // Per Instagram, il worker deve ricevere esclusivamente i dati dell'account specifico
    if (platform != 'Instagram' && platform != 'Facebook') {
      if (widget.selectedAccounts != null && widget.selectedAccounts!.isNotEmpty && widget.socialAccounts != null) {
        final List<Map<String, dynamic>> allSelectedAccounts = [];
        widget.selectedAccounts!.forEach((plat, accountIds) {
          final accountsData = widget.socialAccounts![plat] ?? [];
          for (final accId in accountIds) {
            final accData = accountsData.firstWhere(
              (a) => a['id'] == accId,
              orElse: () {
                return {};
              },
            );
            String? accountDescription;
            if (widget.platformDescriptions != null &&
                widget.platformDescriptions![plat] != null &&
                widget.platformDescriptions![plat]![accId] != null &&
                widget.platformDescriptions![plat]![accId]!.isNotEmpty) {
              accountDescription = widget.platformDescriptions![plat]![accId]!;
            } else {
              accountDescription = null;
            }
            allSelectedAccounts.add({
              'account_display_name': accData['display_name'] ?? accData['name'] ?? accData['username'] ?? '',
              'account_id': accId,
              'account_profile_image_url': accData['profile_picture_url'] ?? accData['profile_image_url'] ?? accData['avatar_url'] ?? accData['thumbnail_url'] ?? '',
              'account_username': accData['username'] ?? accData['name'] ?? '',
              'description': accountDescription,
              'platform_info': '[$plat]',
              if (plat == 'YouTube')
                'title': (widget.platformDescriptions != null &&
                          widget.platformDescriptions!.containsKey('YouTube') &&
                          widget.platformDescriptions!['YouTube']!.containsKey('${accId}_title') &&
                          widget.platformDescriptions!['YouTube']!['${accId}_title']!.isNotEmpty)
                        ? widget.platformDescriptions!['YouTube']!['${accId}_title']!
                        : (_mediaFile != null ? _mediaFile!.path.split('/').last : null),
            });
          }
        });
        print('--- DEBUG allSelectedAccounts (excluded for Instagram) ---');
        print(allSelectedAccounts);
        schedulerData['all_selected_accounts'] = allSelectedAccounts;
      }
    }
    
    print('📋 [SCHEDULER_DATA] Dati preparati per il worker:');
    print('📋 [SCHEDULER_DATA] - Text: ${schedulerData['text']}');
    print('📋 [SCHEDULER_DATA] - Scheduled Time: ${schedulerData['scheduledTime']}');
    print('📋 [SCHEDULER_DATA] - Username: ${schedulerData['username']}');
    print('📋 [SCHEDULER_DATA] - Unique Post ID: ${schedulerData['uniquePostId']}');
    print('📋 [SCHEDULER_DATA] - Media URL: ${schedulerData['mediaUrl'] ?? 'Nessuno'}');
    print('📋 [SCHEDULER_DATA] - Media URLs (carousel): ${schedulerData['media_urls'] ?? 'Nessuno'}');
    print('📋 [SCHEDULER_DATA] - Media Type: ${schedulerData['mediaType'] ?? 'Nessuno'}');
    
    // Aggiungi dati media se disponibili
    if (mediaUrl != null || mediaUrls.isNotEmpty) {
      // Fallback: per i contenuti immagine non generiamo una thumbnail separata.
      // In questo caso usiamo direttamente la stessa URL come thumbnail.
      String? effectiveThumbnailUrl = thumbnailUrl;
      if (mediaType == 'image' && (effectiveThumbnailUrl == null || (effectiveThumbnailUrl is String && effectiveThumbnailUrl.isEmpty))) {
        effectiveThumbnailUrl = mediaUrl;
      }

      schedulerData['mediaUrl'] = mediaUrl;
      schedulerData['mediaType'] = mediaType;
      // Lista completa di URL per caroselli (es. Instagram)
      if (mediaUrls.isNotEmpty) {
        schedulerData['media_urls'] = mediaUrls;
      }
      if (effectiveThumbnailUrl != null) {
        schedulerData['thumbnailUrl'] = effectiveThumbnailUrl;
      }
      
      // Aggiungi durata del video se disponibile
      if (widget.videoFile != null) {
        final videoDuration = await _getVideoDuration();
        if (videoDuration != null) {
          schedulerData['videoDuration'] = videoDuration;
          print('📋 [SCHEDULER_DATA] Video duration added: ${videoDuration['total_seconds']} seconds');
        }
      }
      
      // Aggiungi campi specifici per piattaforma
      _addPlatformSpecificFields(schedulerData, platform, mediaType);
    }
    
    return schedulerData;
  }
  
  // Metodo helper per ottenere username per piattaforma
  String _getUsernameForPlatform(String platform, Map<dynamic, dynamic> accountData) {
    switch (platform) {
      case 'Facebook':
      case 'TikTok':
        return accountData['name'] ?? accountData['display_name'] ?? '';
      case 'YouTube':
        return accountData['channel_name'] ?? accountData['username'] ?? '';
      default:
        return accountData['username'] ?? '';
    }
  }
  
  // Metodo helper per ottenere display_name per piattaforma
  String _getDisplayNameForPlatform(String platform, Map<dynamic, dynamic> accountData) {
    switch (platform) {
      case 'Facebook':
        return accountData['display_name'] ?? accountData['name'] ?? '';
      case 'Instagram':
        return accountData['display_name'] ?? accountData['username'] ?? '';
      case 'Threads':
        return accountData['display_name'] ?? accountData['username'] ?? '';
      case 'TikTok':
        return accountData['display_name'] ?? accountData['name'] ?? '';
      case 'YouTube':
        return accountData['channel_name'] ?? accountData['display_name'] ?? '';
      default:
        return accountData['display_name'] ?? accountData['username'] ?? '';
    }
  }
  
  // Metodo helper per ottenere profile_image_url per piattaforma
  String? _getProfileImageUrlForPlatform(String platform, Map<dynamic, dynamic> accountData) {
    switch (platform) {
      case 'Facebook':
        return accountData['profile_picture_url'] ?? accountData['picture_url'] ?? accountData['profile_image_url'];
      case 'Instagram':
        return accountData['profile_picture_url'] ?? accountData['profile_image_url'];
      case 'Threads':
        return accountData['profile_picture_url'] ?? accountData['profile_image_url'];
      case 'TikTok':
        return accountData['avatar_url'] ?? accountData['profile_picture_url'] ?? accountData['profile_image_url'];
      case 'Twitter':
        return accountData['profile_image_url'] ?? accountData['profile_picture_url'];
      case 'YouTube':
        return accountData['thumbnail_url'] ?? accountData['profile_image_url'] ?? accountData['profile_picture_url'];
      default:
        return accountData['profile_image_url'] ?? accountData['profile_picture_url'];
    }
  }
  
  // Function to resize image for Instagram aspect ratio requirements
  Future<File?> _resizeImageForInstagram(File imageFile) async {
    try {
      // Read the original image
      final bytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);
      
      if (originalImage == null) return null;
      
      final originalWidth = originalImage.width;
      final originalHeight = originalImage.height;
      double aspectRatio = originalWidth / originalHeight;
      
      print('Original image dimensions: ${originalWidth}x${originalHeight}, aspect ratio: $aspectRatio');
      
      // Determine which aspect ratio to use (1:1, 4:5, 1.91:1)
      late img.Image resizedImage;
      
      // Option 1: Square aspect ratio (1:1) - 1080x1080
      if (aspectRatio >= 0.8 && aspectRatio <= 1.2) {
        // Already close to square, make it perfect 1:1
        final size = math.min(originalWidth, originalHeight);
        resizedImage = img.copyCrop(
          originalImage,
          x: (originalWidth - size) ~/ 2,
          y: (originalHeight - size) ~/ 2,
          width: size,
          height: size,
        );
        // Resize to Instagram's recommended 1080x1080
        resizedImage = img.copyResize(resizedImage, width: 1080, height: 1080);
        print('Resizing to square 1:1 (1080x1080)');
      }
      // Option 2: Vertical (4:5) - 1080x1350 for vertical images
      else if (aspectRatio < 0.8) {
        // Vertical image, adapt to 4:5
        final targetWidth = originalWidth;
        final targetHeight = (targetWidth * 5 / 4).round();
        
        if (targetHeight <= originalHeight) {
          // Image is taller than needed, crop it
          resizedImage = img.copyCrop(
            originalImage,
            x: 0,
            y: (originalHeight - targetHeight) ~/ 2,
            width: targetWidth,
            height: targetHeight,
          );
        } else {
          // Image is too narrow, resize it maintaining 4:5 aspect
          final newHeight = originalHeight;
          final newWidth = (newHeight * 4 / 5).round();
          resizedImage = img.copyResize(
            originalImage,
            width: newWidth,
            height: newHeight,
          );
        }
        // Resize to Instagram's recommended 1080x1350
        resizedImage = img.copyResize(resizedImage, width: 1080, height: 1350);
        print('Resizing to vertical 4:5 (1080x1350)');
      }
      // Option 3: Horizontal (1.91:1) - 1080x566 for horizontal images
      else {
        // Horizontal image, adapt to 1.91:1
        final targetHeight = originalHeight;
        final targetWidth = (targetHeight * 1.91).round();
        
        if (targetWidth <= originalWidth) {
          // Image is wider than needed, crop it
          resizedImage = img.copyCrop(
            originalImage,
            x: (originalWidth - targetWidth) ~/ 2,
            y: 0,
            width: targetWidth,
            height: targetHeight,
          );
        } else {
          // Image is too tall, resize it maintaining 1.91:1 aspect
          final newWidth = originalWidth;
          final newHeight = (newWidth / 1.91).round();
          resizedImage = img.copyResize(
            originalImage,
            width: newWidth,
            height: newHeight,
          );
        }
        // Resize to Instagram's recommended 1080x566
        resizedImage = img.copyResize(resizedImage, width: 1080, height: 566);
        print('Resizing to horizontal 1.91:1 (1080x566)');
      }
      
      // Save the resized image to a temporary file
      final tempDir = await getTemporaryDirectory();
      final resizedFile = File('${tempDir.path}/instagram_resized_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final resizedBytes = img.encodeJpg(resizedImage, quality: 90);
      await resizedFile.writeAsBytes(resizedBytes);
      
      print('Resized image dimensions: ${resizedImage.width}x${resizedImage.height}, aspect ratio: ${resizedImage.width / resizedImage.height}');
      print('Resized image saved to: ${resizedFile.path}');
      return resizedFile;
    } catch (error) {
      print('Error resizing image for Instagram: $error');
      return null;
    }
  }

  // Helper function to get signing key for AWS S3 signature
  List<int> _getSigningKey(String secretKey, String dateStamp, String regionName, String serviceName) {
    final kDate = Hmac(sha256, utf8.encode('AWS4$secretKey')).convert(utf8.encode(dateStamp));
    final kRegion = Hmac(sha256, kDate.bytes).convert(utf8.encode(regionName));
    final kService = Hmac(sha256, kRegion.bytes).convert(utf8.encode(serviceName));
    final kSigning = Hmac(sha256, kService.bytes).convert(utf8.encode('aws4_request'));
    return kSigning.bytes;
  }

  // Function to upload resized image to Cloudflare R2
  Future<String?> _uploadResizedImageToCloudflare(File resizedImageFile) async {
    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Utente non autenticato');
      }
      
      // Cloudflare R2 credentials
      final String accessKeyId = '5e181628bad7dc5481c92c6f3899efd6';
      final String secretKey = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
      final String endpoint = 'https://3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com';
      final String bucketName = 'videos';
      final String accountId = '3d945eb681944ec5965fecf275e41a9b';
      final String region = 'auto';
      
      // Generate unique filename for resized image
      final String originalFileName = path.basename(resizedImageFile.path);
      final String fileExtension = path.extension(originalFileName);
      final String baseFileName = path.basenameWithoutExtension(originalFileName);
      final String uniqueFileName = '${baseFileName}_instagram_resized_${DateTime.now().millisecondsSinceEpoch}$fileExtension';
      
      print('Uploading resized image to Cloudflare: $uniqueFileName');
      
      // Read the resized image file
      final bytes = await resizedImageFile.readAsBytes();
      
      // Create the request
      final url = '$endpoint/$bucketName/$uniqueFileName';
      final now = DateTime.now().toUtc();
      final amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
      final dateStamp = DateFormat("yyyyMMdd").format(now);
      
      // Create canonical request
      final canonicalRequest = [
        'PUT',
        '/$bucketName/$uniqueFileName',
        '',
        'content-length:${bytes.length}',
        'content-type:image/jpeg',
        'host:${Uri.parse(endpoint).host}',
        'x-amz-content-sha256:${sha256.convert(bytes).toString()}',
        'x-amz-date:$amzDate',
        '',
        'content-length;content-type;host;x-amz-content-sha256;x-amz-date',
        sha256.convert(bytes).toString()
      ].join('\n');
      
      // Create string to sign
      final stringToSign = [
        'AWS4-HMAC-SHA256',
        amzDate,
        '$dateStamp/$region/s3/aws4_request',
        sha256.convert(utf8.encode(canonicalRequest)).toString()
      ].join('\n');
      
      // Sign the request
      final signingKey = _getSigningKey(secretKey, dateStamp, region, 's3');
      final signature = Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).toString();
      
      // Create authorization header
      final authorization = 'AWS4-HMAC-SHA256 Credential=$accessKeyId/$dateStamp/$region/s3/aws4_request,SignedHeaders=content-length;content-type;host;x-amz-content-sha256;x-amz-date,Signature=$signature';
      
      // Make the request
      final response = await http.put(
        Uri.parse(url),
        headers: {
          'Authorization': authorization,
          'Content-Type': 'image/jpeg',
          'Content-Length': bytes.length.toString(),
          'X-Amz-Content-Sha256': sha256.convert(bytes).toString(),
          'X-Amz-Date': amzDate,
        },
        body: bytes,
      );
      
      if (response.statusCode == 200) {
        // Return the public URL
        final publicUrl = 'https://pub-$accountId.r2.dev/$uniqueFileName';
        print('Resized image uploaded successfully: $publicUrl');
        return publicUrl;
      } else {
        print('Failed to upload resized image: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (error) {
      print('Error uploading resized image to Cloudflare: $error');
      return null;
    }
  }

  // Metodo helper per aggiungere campi specifici per piattaforma
  void _addPlatformSpecificFields(Map<String, dynamic> schedulerData, String platform, String mediaType) {
    switch (platform) {
      case 'Instagram':
        schedulerData['isImage'] = mediaType == 'image';
        schedulerData['contentType'] = 'Reels';
        break;
      case 'Facebook':
        schedulerData['isImage'] = mediaType == 'image';
        break;
      case 'Threads':
        schedulerData['isImage'] = mediaType == 'image';
        break;
      case 'TikTok':
        schedulerData['isImage'] = mediaType == 'image';
        schedulerData['contentType'] = 'Video';
        break;
    }
  }
  
  // Method to schedule post based on platform
  Future<void> _schedulePost() async {
    // Verifica che ci sia un account selezionato
    if (_selectedAccountId == null || _socialAccounts.isEmpty) {
      setState(() {
        _errorMessage = 'No ${widget.platform} account selected or available. Please connect an account.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _schedulingProgress = 0.0;
      _schedulingStatus = 'Starting scheduling...';
    });

    try {
      print('==================== STARTING POST SCHEDULING PROCESS ====================');
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      print('Authenticated user: ${currentUser.uid}');
      final String singleUniquePostId = _generateUniquePostId(currentUser.uid, widget.platform);
      print('🔑 [SINGLE_ID] ID univoco generato per post singolo: $singleUniquePostId');
      _updateSchedulingProgress(10.0, 'Checking connection...');
      await Future.delayed(Duration(milliseconds: 300));
      // Special handling for YouTube - uses direct API instead of workers
      if (widget.platform == 'YouTube') {
        _updateSchedulingProgress(30.0, 'Preparing YouTube...');
        await _scheduleYouTubePost(currentUser, singleUniquePostId).timeout(
          Duration(minutes: 5),
          onTimeout: () {
            throw Exception('YouTube scheduling timed out');
          },
        );
        _updateSchedulingProgress(100.0, 'YouTube scheduled successfully!');
        return;
      }
      // --- MODIFICA: invia una richiesta per ogni account selezionato anche in modalità singola piattaforma ---
      print('ATTILA: selectedAccounts = \\n' + jsonEncode(widget.selectedAccounts));
      print('DEBUG: selectedAccounts[${widget.platform}] = \\n' + jsonEncode(widget.selectedAccounts != null ? widget.selectedAccounts![widget.platform] : null));
      print('DEBUG: selectedAccounts[${widget.platform}]?.length = ' + ((widget.selectedAccounts != null && widget.selectedAccounts![widget.platform] != null) ? widget.selectedAccounts![widget.platform]!.length.toString() : 'null'));
      if (widget.selectedAccounts != null && widget.selectedAccounts![widget.platform] != null && widget.selectedAccounts![widget.platform]!.length > 1) {
        print('DEBUG: Entrato nel ciclo invio per ogni account selezionato!');
        for (final accId in widget.selectedAccounts![widget.platform]!) {
          await _scheduleWorkerBasedPlatform(widget.platform, accId, currentUser, singleUniquePostId);
        }
        _updateSchedulingProgress(100.0, 'Scheduling completed successfully!');
        print('Scheduling completed successfully for all selected accounts');
        if (widget.onSchedulingComplete != null) {
          widget.onSchedulingComplete!();
        }
        _onSchedulingSuccess();
        _showSuccessDialog();
        return;
      }
      // --- FINE MODIFICA ---
      // Per altri casi (un solo account), usa la logica worker esistente
      _updateSchedulingProgress(20.0, 'Checking worker connection...');
      print('Verifying connection to ${widget.platform} worker...');
      final workerUrl = widget.platform == 'Twitter' ? _twitterWorkerUrl : widget.platform == 'Instagram' ? _instagramWorkerUrl : widget.platform == 'Facebook' ? _facebookWorkerUrl : widget.platform == 'Threads' ? _threadsWorkerUrl : _tiktokWorkerUrl;
      final isWorkerReachable = await _checkWorkerConnection(workerUrl).timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print('Worker connection check timed out');
          return false;
        },
      );
      print('Worker reachable: $isWorkerReachable');
      if (!isWorkerReachable) {
        throw Exception('${widget.platform} scheduler worker is not reachable. Please try again later.');
      }
      _updateSchedulingProgress(30.0, 'Retrieving account data...');
      print('Retrieving ${widget.platform} account data: $_selectedAccountId');
      String databasePath;
      if (widget.platform == 'Instagram') {
        databasePath = 'users/${currentUser.uid}/instagram';
      } else if (widget.platform == 'Facebook') {
        databasePath = 'users/${currentUser.uid}/facebook';
      } else if (widget.platform == 'Threads') {
        databasePath = 'users/users/${currentUser.uid}/social_accounts/threads';
      } else if (widget.platform == 'TikTok') {
        databasePath = 'users/${currentUser.uid}/tiktok';
      } else {
        databasePath = 'users/users/${currentUser.uid}/social_accounts/${widget.platform.toLowerCase()}';
      }
      final accountSnapshot = await FirebaseDatabase.instance
          .ref()
          .child(databasePath)
          .get();
      if (!accountSnapshot.exists) {
        print('ERROR: ${widget.platform} account not found in database at path: $databasePath');
        throw Exception('${widget.platform} account not found');
      }
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      print('Account data retrieved: ${accountData['username']}');
      print('Full account data: ${jsonEncode(accountData)}');
      Map<dynamic, dynamic> actualAccountData;
      if (accountData.containsKey(_selectedAccountId)) {
        actualAccountData = accountData[_selectedAccountId] as Map<dynamic, dynamic>;
        print('Extracted nested account data for ID: $_selectedAccountId');
      } else {
        actualAccountData = accountData;
        print('Using root level account data');
      }
      if (actualAccountData['access_token'] == null) {
        print('ERROR: access_token is null');
        throw Exception('${widget.platform} account access_token not found');
      }
      if (widget.platform == 'Facebook') {
        if (actualAccountData['page_id'] == null) {
          print('ERROR: page_id is null for Facebook');
          throw Exception('Facebook account page_id not found');
        }
        if (actualAccountData['name'] == null) {
          print('ERROR: name is null for Facebook');
          throw Exception('Facebook account name not found');
        }
      } else if (widget.platform == 'Threads') {
        if (actualAccountData['user_id'] == null) {
          print('ERROR: user_id is null for Threads');
          throw Exception('Threads account user_id not found');
        }
        if (actualAccountData['username'] == null) {
          print('ERROR: username is null for Threads');
          throw Exception('Threads account username not found');
        }
      } else if (widget.platform == 'TikTok') {
        if (actualAccountData['open_id'] == null) {
          print('ERROR: open_id is null for TikTok');
          throw Exception('TikTok account open_id not found');
        }
        if (actualAccountData['name'] == null) {
          print('ERROR: name is null for TikTok');
          throw Exception('TikTok account name not found');
        }
      } else {
        if (actualAccountData['user_id'] == null) {
          print('ERROR: user_id is null');
          throw Exception('${widget.platform} account user_id not found');
        }
        if (actualAccountData['username'] == null) {
          print('ERROR: username is null');
          throw Exception('${widget.platform} account username not found');
        }
      }
      _updateSchedulingProgress(50.0, 'Preparing media...');
      String? mediaUrl;
      String? thumbnailUrl;
      String mediaType = 'text';
      if (_mediaFile != null || widget.cloudflareUrl != null) {
        _updateSchedulingProgress(60.0, 'Uploading file...');
        print('Step 1: Uploading file to Cloudflare (if not already cached)...');
        mediaUrl = await _uploadFileToCloudflareOnce();
        mediaType = _determineMediaType(mediaUrl);
        thumbnailUrl = _getCachedThumbnailUrl();
        print('Media URL obtained: $mediaUrl');
        print('Media type: $mediaType');
        print('Thumbnail URL: $thumbnailUrl');
      }
      _updateSchedulingProgress(75.0, 'Preparing post data...');
      final DateTime now = DateTime.now();
      final Duration timeZoneOffset = now.timeZoneOffset;
      final int timeZoneOffsetMinutes = timeZoneOffset.inMinutes;
      final String timeZone = DateTime.now().timeZoneName;
      print('Local timezone: $timeZone, offset: $timeZoneOffsetMinutes minutes');
      final int scheduledTimestamp = _scheduledDate.millisecondsSinceEpoch;
      String postText = "";
      if (widget.title != null && widget.title!.isNotEmpty) {
        postText = widget.title!;
      } 
      else if (_textController.text.isNotEmpty) {
        postText = _textController.text;
      }
      else if (widget.description != null && widget.description!.isNotEmpty) {
        postText = widget.description!;
      }
      if (["Instagram", "TikTok", "Facebook", "Threads", "Twitter"].contains(widget.platform) && (postText == null || postText.isEmpty)) {
        postText = "";
      }
      final schedulerData = await _prepareSchedulerData(
        widget.platform,
        _selectedAccountId!,
        actualAccountData,
        currentUser,
        singleUniquePostId // PASSA L'ID UNIVOCO
      );
      _updateSchedulingProgress(85.0, 'Sending data to server...');
      print('🚀 [WORKER_REQUEST] ==================== INVIO DATI AL WORKER ${widget.platform} ====================');
      print('🚀 [WORKER_REQUEST] URL: $workerUrl');
      print('🚀 [WORKER_REQUEST] Method: POST');
      print('🚀 [WORKER_REQUEST] Headers:');
      print('🚀 [WORKER_REQUEST] - Content-Type: application/json');
      print('🚀 [WORKER_REQUEST] - Authorization: Bearer [TOKEN]');
      print('🚀 [WORKER_REQUEST] ==================== PAYLOAD COMPLETO ====================');
      print('🚀 [WORKER_REQUEST] Unique Post ID: ${schedulerData['uniquePostId']}');
      print('🚀 [WORKER_REQUEST] User ID: ${schedulerData['userId']}');
      print('🚀 [WORKER_REQUEST] Account ID: ${schedulerData['accountId']}');
      print('🚀 [WORKER_REQUEST] Username: ${schedulerData['username']}');
      print('🚀 [WORKER_REQUEST] Text: ${schedulerData['text']}');
      print('🚀 [WORKER_REQUEST] Scheduled Time: ${schedulerData['scheduledTime']}');
      print('🚀 [WORKER_REQUEST] Scheduled Date: ${_scheduledDate.toIso8601String()}');
      print('🚀 [WORKER_REQUEST] Media URL: ${schedulerData['mediaUrl'] ?? 'Nessuno'}');
      print('🚀 [WORKER_REQUEST] Media Type: ${schedulerData['mediaType'] ?? 'Nessuno'}');
      print('🚀 [WORKER_REQUEST] Thumbnail URL: ${schedulerData['thumbnailUrl'] ?? 'Nessuno'}');
      print('🚀 [WORKER_REQUEST] Content Type: ${schedulerData['contentType'] ?? 'Nessuno'}');
      print('🚀 [WORKER_REQUEST] Is Image: ${schedulerData['isImage'] ?? false}');
      print('🚀 [WORKER_REQUEST] Time Zone: ${schedulerData['timeZone']}');
      print('🚀 [WORKER_REQUEST] Time Zone Offset: ${schedulerData['timeZoneOffset']}');
      print('🚀 [WORKER_REQUEST] OAuth Access Token: ${schedulerData['oauth']['accessToken'] ? 'PRESENTE' : 'MANCANTE'}');
      print('🚀 [WORKER_REQUEST] OAuth User ID: ${schedulerData['oauth']['userId']}');
      print('🚀 [WORKER_REQUEST] ==================== PAYLOAD JSON COMPLETO ====================');
      print('🚀 [WORKER_REQUEST] ${jsonEncode(schedulerData)}');
      print('🚀 [WORKER_REQUEST] ==================== FINE PAYLOAD ====================');
      final response = await http.post(
        Uri.parse(workerUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await currentUser.getIdToken()}',
        },
        body: jsonEncode(schedulerData),
      ).timeout(Duration(seconds: 30), onTimeout: () {
        print('TIMEOUT in worker request');
        throw Exception('Timeout connecting to ${widget.platform} scheduler worker');
      });
      print('📥 [WORKER_RESPONSE] ==================== RISPOSTA DAL WORKER ${widget.platform} ====================');
      print('📥 [WORKER_RESPONSE] Status Code: ${response.statusCode}');
      print('📥 [WORKER_RESPONSE] Headers: ${response.headers}');
      print('📥 [WORKER_RESPONSE] Body: ${response.body}');
      print('📥 [WORKER_RESPONSE] ==================== FINE RISPOSTA ====================');
      if (response.statusCode != 200) {
        final responseData = jsonDecode(response.body);
        print('ERROR in worker response: ${responseData['error'] ?? 'Unknown error'}');
        throw Exception('Failed to schedule post: ${responseData['error'] ?? 'Unknown error'}');
      }
      final responseData = jsonDecode(response.body);
      print('Post scheduled successfully, ID: ${responseData['id']}');
      _updateSchedulingProgress(95.0, 'Saving data...');
      print('💾 [FIREBASE_SAVE] ==================== SALVATAGGIO SU FIREBASE ====================');
      print('💾 [FIREBASE_SAVE] User ID: ${currentUser.uid}');
      print('💾 [FIREBASE_SAVE] Account ID: $_selectedAccountId');
      print('💾 [FIREBASE_SAVE] Platform: ${widget.platform}');
      print('💾 [FIREBASE_SAVE] Worker ID: ${responseData['id']}');
      print('💾 [FIREBASE_SAVE] Unique Post ID: $singleUniquePostId');
      print('💾 [FIREBASE_SAVE] Firebase Path: users/users/${currentUser.uid}/scheduled_posts/$singleUniquePostId');
      print('💾 [FIREBASE_SAVE] ==================== FINE SALVATAGGIO FIREBASE ====================');
      // Usa i valori effettivi preparati in schedulerData (con fallback)
      final String? savedMediaUrl = (schedulerData['mediaUrl'] as String?) ?? mediaUrl;
      final String savedMediaType = (schedulerData['mediaType'] as String?) ?? mediaType;
      String? savedThumbnailUrl = (schedulerData['thumbnailUrl'] as String?) ?? thumbnailUrl;
      // Per immagini, se la thumbnail manca, usa mediaUrl
      if (savedThumbnailUrl == null && savedMediaUrl != null && savedMediaType == 'image') {
        savedThumbnailUrl = savedMediaUrl;
      }

      // Ottieni mediaUrls se disponibile (per caroselli)
      List<String>? mediaUrls;
      if (schedulerData['media_urls'] != null && schedulerData['media_urls'] is List) {
        mediaUrls = List<String>.from(schedulerData['media_urls']);
      } else if (_cachedCloudflareUrls.isNotEmpty) {
        mediaUrls = _cachedCloudflareUrls;
      }

      await _saveScheduledPostToFirebase(
        currentUser.uid,
        _selectedAccountId!,
        postText,
        _scheduledDate,
        savedMediaUrl,
        savedMediaType,
        responseData['id'],
        widget.platform,
        _getUsernameForPlatform(widget.platform, accountData),
        _getDisplayNameForPlatform(widget.platform, accountData),
        _getProfileImageUrlForPlatform(widget.platform, accountData),
        savedThumbnailUrl,
        singleUniquePostId, // PASSA L'ID UNIVOCO
        schedulerData['videoDuration'], // Aggiungo la durata del video
        null, // Aggiungo il parametro title (null per piattaforme non-YouTube)
        mediaUrls, // Aggiungi lista di media URLs per caroselli
      );
      _updateSchedulingProgress(100.0, 'Scheduling completed successfully!');
      print('Scheduling completed successfully');
      if (widget.onSchedulingComplete != null) {
        print('Calling onSchedulingComplete callback');
        widget.onSchedulingComplete!();
      }
      _onSchedulingSuccess();
      _showSuccessDialog();
    } catch (e) {
      print('==================== ERROR IN POST SCHEDULING ====================');
      print('Error details: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Unable to schedule your post. Please try again.';
          _isLoading = false;
          _schedulingStatus = 'Scheduling failed';
        });
      }
    } finally {
      print('==================== END OF POST SCHEDULING PROCESS ====================');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // Method to schedule YouTube post using direct API
  Future<void> _scheduleYouTubePost(User currentUser, String uniquePostId) async {
    try {
      print('==================== STARTING YOUTUBE SCHEDULING ====================');
      
      // Update scheduling status
      setState(() {
        _platformSchedulingStatus['YouTube'] = false;
        _platformErrors['YouTube'] = null;
        _schedulingStatus = 'Preparing video for YouTube...';
      });
      
      // Validate scheduling date - must be in the future
      final now = DateTime.now();
      
      if (_scheduledDate.isBefore(now)) {
        setState(() {
          _platformErrors['YouTube'] = 'The publication date must be in the future.';
          _platformSchedulingStatus['YouTube'] = false;
        });
        throw Exception('The publication date must be in the future.');
      }
      
      // Get account data from Firebase
      final accountSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(currentUser.uid)
          .child('youtube')
          .child(_selectedAccountId!)
          .get();

      if (!accountSnapshot.exists) {
        setState(() {
          _platformErrors['YouTube'] = 'YouTube account not found. Please reconnect your account.';
          _platformSchedulingStatus['YouTube'] = false;
        });
        throw Exception('YouTube account not found');
      }

      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      print('YouTube account data retrieved: ${accountData['username']}');
      
      // Initialize YouTube service
      final youtubeService = YouTubeService();
      
      // Verify YouTube scheduling date is valid
      if (!youtubeService.isValidPublishDate(_scheduledDate)) {
        setState(() {
          _platformErrors['YouTube'] = 'Invalid scheduling date. Please select a future date.';
          _platformSchedulingStatus['YouTube'] = false;
        });
        throw Exception('YouTube scheduling date is invalid. The date must be in the future.');
      }
      
      // Update status for account-specific scheduling
      setState(() {
        _schedulingStatus = 'Scheduling on channel ${accountData['username']}';
      });
      
      // Get platform-specific description if available
      String videoDescription = widget.description ?? '';
      if (widget.platformDescriptions != null && 
          widget.platformDescriptions!.containsKey('YouTube') && 
          widget.platformDescriptions!['YouTube']!.containsKey(_selectedAccountId!)) {
        videoDescription = widget.platformDescriptions!['YouTube']![_selectedAccountId!]!;
      }
      
      // Determine title to use (SOLO quello personalizzato YouTube, MAI widget.title globale)
      String videoTitle = '';
      if (widget.platformDescriptions != null &&
          widget.platformDescriptions!.containsKey('YouTube') &&
          widget.platformDescriptions!['YouTube']!.containsKey('${_selectedAccountId!}_title') &&
          widget.platformDescriptions!['YouTube']!['${_selectedAccountId!}_title']!.isNotEmpty) {
        videoTitle = widget.platformDescriptions!['YouTube']!['${_selectedAccountId!}_title']!;
      }
      // Fallback: se non c'è titolo personalizzato, usa il nome file
      if (videoTitle.isEmpty && _mediaFile != null) {
        videoTitle = _mediaFile!.path.split('/').last;
      }
      
      print('YouTube scheduling details:');
      print('Title: $videoTitle');
      print('Description: $videoDescription');
      print('Scheduled date: $_scheduledDate');
      print('Scheduled date (UTC): ${_scheduledDate.toUtc()}');
      print('Scheduled date (RFC3339): ${_scheduledDate.toUtc().toIso8601String()}');
      print('Account ID: $_selectedAccountId');
      print('Privacy Status: private (as per YouTube documentation)');
      print('Using videos.insert endpoint with status.privacyStatus and status.publishAt parameters');
      
      // FASE 1: Carica il video su Cloudflare (come per le altre piattaforme)
      String? cloudflareUrl;
      String? thumbnailUrl;
      
      if (_mediaFile != null) {
        setState(() {
          _schedulingStatus = 'Uploading video to Cloudflare...';
        });
        
        print('YouTube: Uploading video to Cloudflare for consistency with other platforms');
        
        // Carica il video su Cloudflare
        cloudflareUrl = await _uploadFileToCloudflareOnce();
        
        // Genera e carica il thumbnail se è un video
        if (cloudflareUrl != null) {
          final mediaType = _determineMediaType(cloudflareUrl);
          if (mediaType == 'video') {
            setState(() {
              _schedulingStatus = 'Generating thumbnail...';
            });
            
            // Usa il thumbnail cached se disponibile
            thumbnailUrl = _getCachedThumbnailUrl();
            
            // Se non c'è un thumbnail cached, generalo
            if (thumbnailUrl == null) {
              try {
                final thumbnailUrlResult = await _generateThumbnail(_mediaFile).timeout(
                  Duration(minutes: 2),
                  onTimeout: () {
                    print('Thumbnail generation timed out, continuing without thumbnail');
                    return null;
                  },
                );
                if (thumbnailUrlResult != null) {
                  thumbnailUrl = thumbnailUrlResult;
                  print('Thumbnail generated and uploaded: $thumbnailUrl');
                }
              } catch (e) {
                print('Error generating thumbnail: $e, continuing without thumbnail');
              }
            } else {
              print('Using cached thumbnail: $thumbnailUrl');
            }
          }
        }
        
        print('YouTube: Cloudflare URL: $cloudflareUrl');
        print('YouTube: Thumbnail URL: $thumbnailUrl');
      } else {
        setState(() {
          _platformErrors['YouTube'] = 'No media file provided for YouTube upload. Please select a video.';
          _platformSchedulingStatus['YouTube'] = false;
        });
        throw Exception('No media file provided for YouTube upload');
      }
      
      // FASE 2: Upload su YouTube usando il file locale (per prestazioni ottimali)
      setState(() {
        _schedulingStatus = 'Uploading to YouTube...';
      });
      
      String? videoId;
      if (_mediaFile != null) {
        print('YouTube: Using local file for direct upload to YouTube (optimal performance)');
        // Get YouTube options for this account, with defaults
        final youtubeOptions = widget.youtubeOptions?[_selectedAccountId!] ?? {
          'categoryId': '22',
          'privacyStatus': 'private', // Per scheduling deve essere private
          'license': 'youtube',
          'notifySubscribers': true,
          'embeddable': true,
          'madeForKids': false,
        };
        // Override privacyStatus to 'private' for scheduling
        youtubeOptions['privacyStatus'] = 'private';
        
        videoId = await youtubeService.uploadScheduledVideoWithSavedAccount(
          videoFile: _mediaFile!,
          title: videoTitle,
          description: videoDescription,
          publishAt: _scheduledDate,
          accountId: _selectedAccountId!,
          youtubeOptions: youtubeOptions,
        );
      }
      
      if (videoId == null) {
        setState(() {
          _platformErrors['YouTube'] = 'Unable to schedule YouTube video. Please try again.';
          _platformSchedulingStatus['YouTube'] = false;
        });
        throw Exception('Error in YouTube scheduling');
      }
      
      print('YouTube video scheduled successfully with ID: $videoId');
      
      // FASE 3: Upload thumbnail personalizzata se disponibile
      if (widget.youtubeThumbnailFile != null) {
        setState(() {
          _schedulingStatus = 'Upload YouTube thumbnail...';
        });
        
        try {
          final thumbnailFile = widget.youtubeThumbnailFile!;
          final bytes = await thumbnailFile.readAsBytes();
          final fileSize = bytes.length;
          final mimeType = thumbnailFile.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
          
          print('***YOUTUBE THUMBNAIL*** post_scheduler_page.dart: path: \'${thumbnailFile.path}\', size: ${fileSize} bytes, mime: $mimeType');
          
          if (fileSize > 2 * 1024 * 1024) {
            print('***YOUTUBE THUMBNAIL ERROR***: Thumbnail file exceeds 2MB, cannot upload.');
            setState(() {
              _schedulingStatus = 'Thumbnail too large (>2MB), not uploaded!';
            });
          } else if (!(mimeType == 'image/jpeg' || mimeType == 'image/png')) {
            print('***YOUTUBE THUMBNAIL ERROR***: Thumbnail must be JPEG or PNG.');
            setState(() {
              _schedulingStatus = 'Thumbnail must be JPEG or PNG!';
            });
          } else {
            // Ottieni il token di accesso per YouTube usando GoogleSignIn
            try {
              GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
              
              // Se non c'è un account già autorizzato, richiedi l'accesso
              if (googleUser == null) {
                googleUser = await _googleSignIn.signIn();
              }
              
              if (googleUser != null) {
                final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
                
                if (googleAuth.accessToken != null) {
                  print('Uploading custom thumbnail for YouTube video: $videoId');
                  final thumbnailResponse = await http.post(
                    Uri.parse('https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=$videoId'),
                    headers: {
                      'Authorization': 'Bearer ${googleAuth.accessToken}',
                      'Content-Type': mimeType,
                    },
                    body: bytes,
                  ).timeout(
                    const Duration(seconds: 30),
                    onTimeout: () => throw TimeoutException('Thumbnail upload request timed out.'),
                  );
                  
                  if (thumbnailResponse.statusCode == 200) {
                    setState(() {
                      _schedulingStatus = 'Custom thumbnail uploaded successfully!';
                    });
                    print('Custom thumbnail uploaded successfully to YouTube!');
                  } else {
                    print('Warning: Failed to upload custom thumbnail: \'${thumbnailResponse.body}\'');
                    setState(() {
                      _schedulingStatus = 'Warning: Thumbnail upload failed, but video is ready!';
                    });
                  }
                } else {
                  print('Warning: No access token available for thumbnail upload');
                  setState(() {
                    _schedulingStatus = 'Warning: No access token for thumbnail upload';
                  });
                }
              } else {
                print('Warning: GoogleSignIn failed, cannot upload thumbnail');
                setState(() {
                  _schedulingStatus = 'Warning: GoogleSignIn failed, thumbnail not uploaded';
                });
              }
            } catch (e) {
              print('Warning: Error getting GoogleSignIn token: $e');
              setState(() {
                _schedulingStatus = 'Warning: Error getting access token, thumbnail not uploaded';
              });
            }
          }
        } catch (e) {
          print('Warning: Error uploading custom thumbnail: $e');
          setState(() {
            _schedulingStatus = 'Warning: Thumbnail upload failed, but video is ready!';
          });
        }
      }
      
      // Update status to completed
      setState(() {
        _platformSchedulingStatus['YouTube'] = true;
        _platformErrors['YouTube'] = null;
        _schedulingStatus = 'Video scheduled successfully on YouTube';
        _completedPlatforms++;
      });
      
      // Save the scheduled post to Firebase for tracking
      print('Saving YouTube scheduled post to Firebase');
      // Per YouTube non ci sono caroselli, quindi mediaUrls è null
      await _saveScheduledPostToFirebase(
        currentUser.uid,
        _selectedAccountId!,
        videoDescription,
        _scheduledDate,
        cloudflareUrl, // Ora salviamo anche l'URL Cloudflare per YouTube
        'video',
        videoId,
        'YouTube',
        _getUsernameForPlatform('YouTube', accountData),
        _getDisplayNameForPlatform('YouTube', accountData), // Aggiungo il display_name
        _getProfileImageUrlForPlatform('YouTube', accountData), // Aggiungo la profile_image_url
        thumbnailUrl, // Ora salviamo anche l'URL del thumbnail per YouTube
        uniquePostId, // Usa l'ID passato
        null, // Per YouTube, la durata del video viene gestita diversamente
        // AGGIUNTA: Passa anche il titolo personalizzato
        videoTitle,
        null, // YouTube non supporta caroselli, quindi mediaUrls è null
      );
      
      // Show success message and navigate back
      print('YouTube scheduling completed successfully');
      
      // Per utenti non premium, mostra il popup con i crediti sottratti
      if (widget.platform == 'YouTube' && !_isPremium) {
        _showYouTubeSuccessDialog();
      } else {
        // Per utenti premium YouTube e altre piattaforme, usa il popup di successo
        // Call onSchedulingComplete if provided
        if (widget.onSchedulingComplete != null) {
          print('Calling onSchedulingComplete callback');
          widget.onSchedulingComplete!();
        }
        _showSuccessDialog();
      }
      
    } catch (e) {
      print('==================== ERROR IN YOUTUBE SCHEDULING ====================');
      print('Error details: $e');
      
      // Update error status
      setState(() {
        _platformErrors['YouTube'] = 'Unable to schedule YouTube video. Please try again.';
        _platformSchedulingStatus['YouTube'] = false;
      });
      
      throw e; // Re-throw to be handled by the main error handler
    }
  }
  
  // Nuovo metodo per schedulare YouTube e restituire i risultati
  Future<Map<String, dynamic>?> _scheduleYouTubePostWithResult(User currentUser, String uniquePostId) async {
    try {
      print('==================== STARTING YOUTUBE SCHEDULING WITH RESULT ====================');
      
      // Update scheduling status
      setState(() {
        _platformSchedulingStatus['YouTube'] = false;
        _platformErrors['YouTube'] = null;
        _schedulingStatus = 'Preparing video for YouTube...';
      });
      
      // Validate scheduling date - must be in the future
      final now = DateTime.now();
      
      if (_scheduledDate.isBefore(now)) {
        setState(() {
          _platformErrors['YouTube'] = 'The publication date must be in the future.';
          _platformSchedulingStatus['YouTube'] = false;
        });
        throw Exception('The publication date must be in the future.');
      }
      
      // Get account data from Firebase
      final accountSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(currentUser.uid)
          .child('youtube')
          .child(_selectedAccountId!)
          .get();

      if (!accountSnapshot.exists) {
        setState(() {
          _platformErrors['YouTube'] = 'YouTube account not found. Please reconnect your account.';
          _platformSchedulingStatus['YouTube'] = false;
        });
        throw Exception('YouTube account not found');
      }

      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      print('YouTube account data retrieved: ${accountData['username']}');
      
      // Initialize YouTube service
      final youtubeService = YouTubeService();
      
      // Verify YouTube scheduling date is valid
      if (!youtubeService.isValidPublishDate(_scheduledDate)) {
        setState(() {
          _platformErrors['YouTube'] = 'Invalid scheduling date. Please select a future date.';
          _platformSchedulingStatus['YouTube'] = false;
        });
        throw Exception('YouTube scheduling date is invalid. The date must be in the future.');
      }
      
      // Get platform-specific description if available
      String videoDescription = widget.description ?? '';
      if (widget.platformDescriptions != null && 
          widget.platformDescriptions!.containsKey('YouTube') && 
          widget.platformDescriptions!['YouTube']!.containsKey(_selectedAccountId!)) {
        videoDescription = widget.platformDescriptions!['YouTube']![_selectedAccountId!]!;
      }
      
      // Determine title to use (SOLO quello personalizzato YouTube, MAI widget.title globale)
      String videoTitle = '';
      if (widget.platformDescriptions != null &&
          widget.platformDescriptions!.containsKey('YouTube') &&
          widget.platformDescriptions!['YouTube']!.containsKey('${_selectedAccountId!}_title') &&
          widget.platformDescriptions!['YouTube']!['${_selectedAccountId!}_title']!.isNotEmpty) {
        videoTitle = widget.platformDescriptions!['YouTube']!['${_selectedAccountId!}_title']!;
      }
      // Fallback: se non c'è titolo personalizzato, usa il nome file
      if (videoTitle.isEmpty && _mediaFile != null) {
        videoTitle = _mediaFile!.path.split('/').last;
      }
      
      print('YouTube scheduling details:');
      print('Title: $videoTitle');
      print('Description: $videoDescription');
      print('Scheduled date: $_scheduledDate');
      print('Scheduled date (UTC): ${_scheduledDate.toUtc()}');
      print('Scheduled date (RFC3339): ${_scheduledDate.toUtc().toIso8601String()}');
      print('Account ID: $_selectedAccountId');
      print('Privacy Status: private (as per YouTube documentation)');
      print('Using videos.insert endpoint with status.privacyStatus and status.publishAt parameters');
      
      // FASE 1: Carica il video su Cloudflare (come per le altre piattaforme)
      String? cloudflareUrl;
      String? thumbnailUrl;
      
      if (_mediaFile != null) {
        setState(() {
          _schedulingStatus = 'Uploading video to Cloudflare...';
        });
        
        print('YouTube: Uploading video to Cloudflare for consistency with other platforms');
        
        // Carica il video su Cloudflare
        cloudflareUrl = await _uploadFileToCloudflareOnce();
        
        // Genera e carica il thumbnail se è un video
        if (cloudflareUrl != null) {
          final mediaType = _determineMediaType(cloudflareUrl);
          if (mediaType == 'video') {
            setState(() {
              _schedulingStatus = 'Generating thumbnail...';
            });
            
            // Usa il thumbnail cached se disponibile
            thumbnailUrl = _getCachedThumbnailUrl();
            
            // Se non c'è un thumbnail cached, generalo
            if (thumbnailUrl == null) {
              try {
                final thumbnailUrlResult = await _generateThumbnail(_mediaFile).timeout(
                  Duration(minutes: 2),
                  onTimeout: () {
                    print('Thumbnail generation timed out, continuing without thumbnail');
                    return null;
                  },
                );
                if (thumbnailUrlResult != null) {
                  thumbnailUrl = thumbnailUrlResult;
                  print('Thumbnail generated and uploaded: $thumbnailUrl');
                }
              } catch (e) {
                print('Error generating thumbnail: $e, continuing without thumbnail');
              }
            } else {
              print('Using cached thumbnail: $thumbnailUrl');
            }
          }
        }
        
        print('YouTube: Cloudflare URL: $cloudflareUrl');
        print('YouTube: Thumbnail URL: $thumbnailUrl');
      } else {
        throw Exception('No media file provided for YouTube upload');
      }
      
      // FASE 2: Upload su YouTube usando il file locale (per prestazioni ottimali)
      setState(() {
        _schedulingStatus = 'Uploading to YouTube...';
      });
      
      String? videoId;
      if (_mediaFile != null) {
        print('YouTube: Using local file for direct upload to YouTube (optimal performance)');
        // Get YouTube options for this account, with defaults
        final youtubeOptions = widget.youtubeOptions?[_selectedAccountId!] ?? {
          'categoryId': '22',
          'privacyStatus': 'private', // Per scheduling deve essere private
          'license': 'youtube',
          'notifySubscribers': true,
          'embeddable': true,
          'madeForKids': false,
        };
        // Override privacyStatus to 'private' for scheduling
        youtubeOptions['privacyStatus'] = 'private';
        
        videoId = await youtubeService.uploadScheduledVideoWithSavedAccount(
          videoFile: _mediaFile!,
          title: videoTitle,
          description: videoDescription,
          publishAt: _scheduledDate,
          accountId: _selectedAccountId!,
          youtubeOptions: youtubeOptions,
        );
      }
      
      if (videoId == null) {
        throw Exception('Error in YouTube scheduling');
      }
      
      print('YouTube video scheduled successfully with ID: $videoId');
      
      // FASE 3: Upload thumbnail personalizzata se disponibile
      if (widget.youtubeThumbnailFile != null) {
        setState(() {
          _schedulingStatus = 'Upload YouTube thumbnail...';
        });
        
        try {
          final thumbnailFile = widget.youtubeThumbnailFile!;
          final bytes = await thumbnailFile.readAsBytes();
          final fileSize = bytes.length;
          final mimeType = thumbnailFile.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
          
          print('***YOUTUBE THUMBNAIL*** post_scheduler_page.dart: path: \'${thumbnailFile.path}\', size: ${fileSize} bytes, mime: $mimeType');
          
          if (fileSize > 2 * 1024 * 1024) {
            print('***YOUTUBE THUMBNAIL ERROR***: Thumbnail file exceeds 2MB, cannot upload.');
            setState(() {
              _schedulingStatus = 'Thumbnail too large (>2MB), not uploaded!';
            });
          } else if (!(mimeType == 'image/jpeg' || mimeType == 'image/png')) {
            print('***YOUTUBE THUMBNAIL ERROR***: Thumbnail must be JPEG or PNG.');
            setState(() {
              _schedulingStatus = 'Thumbnail must be JPEG or PNG!';
            });
          } else {
            // Ottieni il token di accesso per YouTube usando GoogleSignIn
            try {
              GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
              
              // Se non c'è un account già autorizzato, richiedi l'accesso
              if (googleUser == null) {
                googleUser = await _googleSignIn.signIn();
              }
              
              if (googleUser != null) {
                final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
                
                if (googleAuth.accessToken != null) {
                  print('Uploading custom thumbnail for YouTube video: $videoId');
                  final thumbnailResponse = await http.post(
                    Uri.parse('https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=$videoId'),
                    headers: {
                      'Authorization': 'Bearer ${googleAuth.accessToken}',
                      'Content-Type': mimeType,
                    },
                    body: bytes,
                  ).timeout(
                    const Duration(seconds: 30),
                    onTimeout: () => throw TimeoutException('Thumbnail upload request timed out.'),
                  );
                  
                  if (thumbnailResponse.statusCode == 200) {
                    setState(() {
                      _schedulingStatus = 'Custom thumbnail uploaded successfully!';
                    });
                    print('Custom thumbnail uploaded successfully to YouTube!');
                  } else {
                    print('Warning: Failed to upload custom thumbnail: \'${thumbnailResponse.body}\'');
                    setState(() {
                      _schedulingStatus = 'Warning: Thumbnail upload failed, but video is ready!';
                    });
                  }
                } else {
                  print('Warning: No access token available for thumbnail upload');
                  setState(() {
                    _schedulingStatus = 'Warning: No access token for thumbnail upload';
                  });
                }
              } else {
                print('Warning: GoogleSignIn failed, cannot upload thumbnail');
                setState(() {
                  _schedulingStatus = 'Warning: GoogleSignIn failed, thumbnail not uploaded';
                });
              }
            } catch (e) {
              print('Warning: Error getting GoogleSignIn token: $e');
              setState(() {
                _schedulingStatus = 'Warning: Error getting access token, thumbnail not uploaded';
              });
            }
          }
        } catch (e) {
          print('Warning: Error uploading custom thumbnail: $e');
          setState(() {
            _schedulingStatus = 'Warning: Thumbnail upload failed, but video is ready!';
          });
        }
      }
      
      // Restituisci i risultati invece di salvare su Firebase
      return {
        'platform': 'YouTube',
        'accountId': _selectedAccountId!,
        'workerId': videoId, // Per YouTube, il videoId è il workerId
        'accountUsername': _getUsernameForPlatform('YouTube', accountData),
        'accountDisplayName': _getDisplayNameForPlatform('YouTube', accountData),
        'accountProfileImageUrl': _getProfileImageUrlForPlatform('YouTube', accountData),
        'cloudflareUrl': cloudflareUrl, // Aggiungiamo anche l'URL Cloudflare
        'thumbnailUrl': thumbnailUrl, // Aggiungiamo anche l'URL del thumbnail
        // allineiamo i nomi campi per il salvataggio aggregato
        'mediaUrl': cloudflareUrl,
        'mediaType': 'video',
      };
      
    } catch (e) {
      print('==================== ERROR IN YOUTUBE SCHEDULING WITH RESULT ====================');
      print('Error details: $e');
      throw e; // Re-throw to be handled by the main error handler
    }
  }
  
  // Helper method to prepare OAuth data based on platform
  Map<String, dynamic> _prepareOAuthData(Map<dynamic, dynamic> accountData, String platform) {
    if (platform == 'YouTube') {
      // YouTube non usa OAuth tradizionale, usa GoogleSignIn
      return {
        'channelId': accountData['channel_id'],
        'channelName': accountData['channel_name'],
      };
    } else if (platform == 'Twitter') {
      return {
        'accessToken': accountData['access_token'],
        'accessTokenSecret': accountData['access_token_secret'] ?? accountData['token_secret'],
        'consumerKey': '2pGcVCVRzfONybFtWUsZ1ODN9',
        'consumerSecret': 'JLQIoL9MBSRvYhNTwVQfgs521Fi20rE0qMKGt4ewp6F35px7ZX',
      };
    } else if (platform == 'Instagram') {
      return {
        'accessToken': accountData['access_token'],
        'userId': accountData['user_id'],
      };
    } else if (platform == 'Facebook') {
      return {
        'accessToken': accountData['access_token'],
        'userId': accountData['page_id'] ?? accountData['user_id'],
      };
    } else if (platform == 'Threads') {
      return {
        'accessToken': accountData['access_token'],
        'userId': accountData['user_id'],
      };
    } else if (platform == 'TikTok') {
      return {
        'accessToken': accountData['access_token'],
        'userId': accountData['open_id'],
      };
    }
    throw Exception('Unsupported platform: $platform');
  }
  
  // Modified method to check worker connection
  Future<bool> _checkWorkerConnection(String workerUrl) async {
    try {
      print('Verifying connection to worker: $workerUrl');
      
      // Use the test endpoint instead of the schedule endpoint for connection check
      // The schedule endpoint only accepts POST, but we need GET for connection check
      final testUrl = workerUrl.replaceAll('/api/schedule', '/test');
      print('Using test endpoint for connection check: $testUrl');
      
      final response = await http.get(
        Uri.parse(testUrl),
      ).timeout(Duration(seconds: 10), onTimeout: () {
        print('Timeout in worker connection check');
        throw Exception('Connection timeout');
      });
      
      print('Response from worker: ${response.statusCode}');
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Error checking worker connection: $e');
      return false;
    }
  }
  
  // Helper method to handle media upload
  Future<String?> _handleMediaUpload(File? mediaFile, String? cloudflareUrl) async {
    if (mediaFile != null || cloudflareUrl != null) {
      if (mediaFile != null) {
        print('Media file present, uploading to Cloudflare R2');
        return await _uploadMediaToCloudflareR2(mediaFile, _getContentType(mediaFile.path.split('.').last));
      } else if (cloudflareUrl != null) {
        print('URL Cloudflare provided, using it directly');
        return cloudflareUrl;
      }
    }
    return null;
  }
  
  // Helper method to determine media type based on URL
  String _determineMediaType(String? mediaUrl) {
    if (mediaUrl != null) {
      final String urlLower = mediaUrl.toLowerCase();
      if (urlLower.endsWith('.jpg') || urlLower.endsWith('.jpeg') || 
          urlLower.endsWith('.png') || urlLower.endsWith('.gif')) {
        return 'image';
      } else if (urlLower.endsWith('.mp4') || urlLower.endsWith('.mov') || 
                urlLower.endsWith('.avi')) {
        return 'video';
      }
    }
    return 'text';
  }
  
  // Helper method to determine media type based on file
  String _determineMediaTypeFromFile(File mediaFile) {
    final String filePath = mediaFile.path.toLowerCase();
    if (filePath.endsWith('.jpg') || filePath.endsWith('.jpeg') || 
        filePath.endsWith('.png') || filePath.endsWith('.gif')) {
      return 'image';
    } else if (filePath.endsWith('.mp4') || filePath.endsWith('.mov') || 
              filePath.endsWith('.avi')) {
      return 'video';
    }
    return 'text';
  }
  
  // Helper method to generate thumbnail
  Future<String?> _generateThumbnail(File? mediaFile) async {
    if (mediaFile == null) {
      return null;
    }
    
    try {
      print('Generating thumbnail for video: ${mediaFile.path}');
      
      // Use video_thumbnail package to generate thumbnail
      final thumbnailBytes = await VideoThumbnail.thumbnailData(
        video: mediaFile.path,
        imageFormat: ImageFormat.JPEG,
        quality: 80,
        maxWidth: 320, // Reasonable width for thumbnails
        timeMs: 500, // Take frame at 500ms
      );
      
      if (thumbnailBytes == null) {
        print('Failed to generate thumbnail: thumbnailBytes is null');
        return null;
      }
      
      // Save the thumbnail locally
      final thumbnailFile = await _saveThumbnailToFile(thumbnailBytes);
      if (thumbnailFile != null) {
        print('Thumbnail generated and saved at: ${thumbnailFile.path}');
        
        // Upload thumbnail to Cloudflare
        final thumbnailUrl = await _uploadThumbnailToCloudflare(thumbnailFile);
        if (thumbnailUrl != null) {
          print('Thumbnail uploaded to Cloudflare: $thumbnailUrl');
          return thumbnailUrl;
        } else {
          print('Failed to upload thumbnail to Cloudflare');
          return null;
        }
      } else {
        print('Failed to save thumbnail file');
        return null;
      }
    } catch (e) {
      print('Error generating thumbnail: $e');
      return null;
    }
  }
  
  // Save thumbnail bytes to a file
  Future<File?> _saveThumbnailToFile(Uint8List thumbnailBytes) async {
    try {
      final fileName = _mediaFile!.path.split('/').last;
      final thumbnailFileName = '${fileName.split('.').first}_thumbnail.jpg';
      
      // Get the app's temporary directory
      final directory = await getTemporaryDirectory();
      final thumbnailPath = '${directory.path}/$thumbnailFileName';
      
      // Save the file
      final file = File(thumbnailPath);
      await file.writeAsBytes(thumbnailBytes);
      return file;
    } catch (e) {
      print('Error saving thumbnail file: $e');
      return null;
    }
  }
  
  // Upload thumbnail to Cloudflare R2
  Future<String?> _uploadThumbnailToCloudflare(File thumbnailFile) async {
    try {
      // Generate a unique filename for the thumbnail
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final String thumbnailFileName = 'thumb_${timestamp}_${currentUser.uid}.jpg';
      
      // Cloudflare R2 credentials
      final String accessKeyId = '5e181628bad7dc5481c92c6f3899efd6';
      final String secretKey = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
      final String endpoint = 'https://3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com';
      final String bucketName = 'videos';
      final String accountId = '3d945eb681944ec5965fecf275e41a9b';
      final String region = 'auto';
      
      // Get file bytes and size
      final bytes = await thumbnailFile.readAsBytes();
      final contentLength = bytes.length;
      
      // Calculate SHA-256 hash of content
      final List<int> contentHash = sha256.convert(bytes).bytes;
      final String payloadHash = hex.encode(contentHash);
      
      // Set up request information
      final String httpMethod = 'PUT';
      final String contentType = 'image/jpeg';
      
      // SigV4 requires date in ISO8601 format
      final now = DateTime.now().toUtc();
      final String amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
      final String dateStamp = DateFormat("yyyyMMdd").format(now);
      
      // Host and URI
      final Uri uri = Uri.parse('$endpoint/$bucketName/$thumbnailFileName');
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
      
      // Sort headers lexicographically
      final sortedHeaderKeys = headers.keys.toList()..sort();
      for (final key in sortedHeaderKeys) {
        canonicalHeaders += '${key.toLowerCase()}:${headers[key]}\n';
        signedHeaders += '${key.toLowerCase()};';
      }
      signedHeaders = signedHeaders.substring(0, signedHeaders.length - 1);
      
      // Canonical request
      final String canonicalUri = '/$bucketName/$thumbnailFileName';
      final String canonicalQueryString = '';
      final String canonicalRequest = '$httpMethod\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
      
      // String to sign
      final String algorithm = 'AWS4-HMAC-SHA256';
      final String scope = '$dateStamp/$region/s3/aws4_request';
      final String stringToSign = '$algorithm\n$amzDate\n$scope\n${hex.encode(sha256.convert(utf8.encode(canonicalRequest)).bytes)}';
      
      // Signature
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
      final String uploadUrl = '$endpoint/$bucketName/$thumbnailFileName';
      
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
        // Generate public URL in the correct format
        final String publicUrl = 'https://pub-$accountId.r2.dev/$thumbnailFileName';
        
        print('Thumbnail uploaded successfully to Cloudflare R2');
        print('Thumbnail URL: $publicUrl');
        
        return publicUrl;
      } else {
        throw Exception('Error uploading thumbnail to Cloudflare R2: Code ${response.statusCode}, Response: $responseBody');
      }
    } catch (e) {
      print('Error uploading thumbnail to Cloudflare: $e');
      return null;
    }
  }
  
  // Helper method to generate video thumbnail
  Future<String?> _generateVideoThumbnail(File videoFile) async {
    // REMOVED: This method has been replaced by _generateThumbnail which uses video_thumbnail package
    // The new method generates real thumbnails from video frames instead of placeholder JPEGs
    return null;
  }
  
  // Helper method to upload to Cloudflare R2 with a specific filename
  Future<String> _uploadToCloudflareR2(File file, String contentType, String fileName) async {
    try {
      print('Inizio upload file su Cloudflare R2: ${file.path}');
      print('Nome file: $fileName, Content-Type: $contentType');
      print('Dimensione file: ${await file.length()} bytes');
      
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      
      final String fileKey = fileName;
      
      // Cloudflare R2 credentials - using correct credentials from storage.md
      final String accessKeyId = '5e181628bad7dc5481c92c6f3899efd6';
      final String secretKey = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
      final String endpoint = 'https://3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com';
      final String bucketName = 'videos';
      final String accountId = '3d945eb681944ec5965fecf275e41a9b';
      final String region = 'auto';
      
      // Get file bytes and size
      final bytes = await file.readAsBytes();
      final contentLength = bytes.length;
      
      // Calculate SHA-256 hash of content
      final List<int> contentHash = sha256.convert(bytes).bytes;
      final String payloadHash = hex.encode(contentHash);
      
      // Set up request information
      final String httpMethod = 'PUT';
      
      // SigV4 requires data in ISO8601 format
      final now = DateTime.now().toUtc();
      final String amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
      final String dateStamp = DateFormat("yyyyMMdd").format(now);
      
      // Host and URI
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
      
      // Sort headers lexicographically
      final sortedHeaderKeys = headers.keys.toList()..sort();
      for (final key in sortedHeaderKeys) {
        canonicalHeaders += '${key.toLowerCase()}:${headers[key]}\n';
        signedHeaders += '${key.toLowerCase()};';
      }
      signedHeaders = signedHeaders.substring(0, signedHeaders.length - 1); // Remove the last semicolon
      
      // Canonical request
      final String canonicalUri = '/$bucketName/$fileKey';
      final String canonicalQueryString = '';
      final String canonicalRequest = '$httpMethod\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
      
      // String to sign
      final String algorithm = 'AWS4-HMAC-SHA256';
      final String scope = '$dateStamp/$region/s3/aws4_request';
      final String stringToSign = '$algorithm\n$amzDate\n$scope\n${hex.encode(sha256.convert(utf8.encode(canonicalRequest)).bytes)}';
      
      // Sign
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
      
      // Setup progress tracking
      int bytesUploaded = 0;
      final streamedRequest = http.StreamedRequest(
        request.method,
        request.url,
      );
      
      // Add all headers to streamed request
      request.headers.forEach((key, value) {
        streamedRequest.headers[key] = value;
      });
      
      // Set up progress tracking as data is sent
      final progressStream = Stream<List<int>>.fromIterable(
        [bytes],
      ).transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            bytesUploaded += data.length;
            final progress = bytesUploaded / contentLength;
            print('Upload progress: ${(progress * 100).toInt()}%');
            sink.add(data);
          },
        ),
      );
      
      // Add the progress stream to the request
      await for (final chunk in progressStream) {
        streamedRequest.sink.add(chunk);
      }
      streamedRequest.sink.close();
      
      // Send the request and get the response
      final streamedResponse = await streamedRequest.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Generate public URL in the correct format
        // Use the format pub-[accountId].r2.dev
        final String publicUrl = 'https://pub-$accountId.r2.dev/$fileKey';
        
        print('File uploaded successfully to Cloudflare R2');
        print('Generated public URL: $publicUrl');
        
        // Verify that the URL is accessible
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
  
  // Helper method to save scheduled post to Firebase
  Future<void> _saveScheduledPostToFirebase(
    String userId,
    String accountId,
    String text,
    DateTime scheduledDate,
    String? mediaUrl,
    String mediaType,
    String workerId,
    String platform,
    String? accountUsername,
    String? accountDisplayName, // Aggiungo il parametro per il display_name
    String? accountProfileImageUrl, // Aggiungo il parametro per la profile_image_url
    String? thumbnailUrl, // Aggiungo il parametro per la thumbnail URL
    String? uniquePostId, // Aggiungo il parametro per l'ID univoco
    Map<String, int>? videoDuration, // Aggiungo il parametro per la durata del video
    String? title, // Aggiungo il parametro per il titolo personalizzato
    List<String>? mediaUrls, // Aggiungo il parametro per la lista di media URLs (caroselli)
  ) async {
    try {
      print('🔥 [FIREBASE_SAVE_INTERNAL] Inizio salvataggio su Firebase:');
      print('🔥 [FIREBASE_SAVE_INTERNAL] - User ID: $userId');
      print('🔥 [FIREBASE_SAVE_INTERNAL] - Account ID: $accountId');
      print('🔥 [FIREBASE_SAVE_INTERNAL] - Platform: $platform');
      print('🔥 [FIREBASE_SAVE_INTERNAL] - Worker ID: $workerId');
      print('🔥 [FIREBASE_SAVE_INTERNAL] - Unique Post ID: $uniquePostId');
      
      // Se siamo in modalità multi-piattaforma, non salvare qui
      // Il salvataggio verrà gestito dal metodo _saveMultiPlatformPostToFirebase
      if (_isMultiPlatformScheduling) {
        print('🔥 [FIREBASE_SAVE_INTERNAL] Multi-platform scheduling detected, skipping individual save for $platform');
        return;
      }
      
      final postRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(userId)
          .child('scheduled_posts')
          .child(uniquePostId!); // Usa l'ID univoco come chiave invece di push()
      
      // Ottieni descrizione e titolo personalizzati per questo account se disponibili
      String? customTitle;
      String? customDescription;
      
      // Usa la stessa logica di upload_confirmation_page.dart
      // Se c'è una descrizione personalizzata in platformDescriptions, usala
      // Altrimenti, usa la descrizione globale SOLO se l'utente non ha disattivato il toggle
      if (widget.platformDescriptions != null && 
          widget.platformDescriptions!.containsKey(platform) && 
          widget.platformDescriptions![platform]!.containsKey(accountId)) {
        final platformSpecificText = widget.platformDescriptions![platform]![accountId];
        if (platformSpecificText != null && platformSpecificText.isNotEmpty) {
          customDescription = platformSpecificText;
        }
        // Se la descrizione personalizzata è vuota, non usare quella globale
        // (l'utente ha disattivato il toggle e lasciato il campo vuoto)
      } else {
        // Se non c'è una chiave per questo account in platformDescriptions,
        // significa che l'utente ha disattivato il toggle per usare il contenuto globale
        // Non salvare nessuna descrizione
        customDescription = null;
      }
      
      // Per il titolo personalizzato, usa SOLO quello specifico per YouTube
      if (platform == 'YouTube' && title != null && title.isNotEmpty) {
        customTitle = title;
      } else if (platform != 'YouTube' && widget.title != null && widget.title!.isNotEmpty) {
        customTitle = widget.title!;
      }
      
      final postData = {
        'user_id': userId, // Aggiungo l'ID dell'utente attuale
        'account_id': accountId,
        'text': text,
        'scheduled_time': scheduledDate.millisecondsSinceEpoch,
        'status': 'scheduled',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'worker_id': workerId,
        'platform': platform,
        'account_username': accountUsername, // Aggiungo il nome del profilo social
        'account_display_name': accountDisplayName, // Aggiungo il display_name dell'account
        'account_profile_image_url': accountProfileImageUrl, // Aggiungo la profile_image_url dell'account
        'thumbnail_url': thumbnailUrl, // Aggiungo la thumbnail URL
        'unique_post_id': uniquePostId, // Aggiungo l'ID univoco per il worker
      };
      
      // Aggiungi durata del video se disponibile
      if (videoDuration != null) {
        postData['video_duration_seconds'] = videoDuration['total_seconds'];
        postData['video_duration_minutes'] = videoDuration['minutes'];
        postData['video_duration_remaining_seconds'] = videoDuration['seconds'];
        print('🔥 [FIREBASE_SAVE_INTERNAL] Video duration added: ${videoDuration['total_seconds']} seconds');
      }
      
      // Aggiungi lista di media URLs se disponibile (per caroselli)
      if (mediaUrls != null && mediaUrls.isNotEmpty) {
        // Salva come oggetto con indici numerici per Firebase
        Map<String, String> mediaUrlsMap = {};
        for (int i = 0; i < mediaUrls.length; i++) {
          mediaUrlsMap[i.toString()] = mediaUrls[i];
        }
        postData['media_urls'] = mediaUrlsMap;
        print('📸 [FIREBASE_SAVE_INTERNAL] Media URLs salvati: ${mediaUrls.length} URL');
      }
      
      // Aggiungi titolo e descrizione personalizzati se disponibili
      if (customTitle != null) {
        postData['title'] = customTitle;
      }
      if (customDescription != null) {
        postData['description'] = customDescription;
      }
      
      // Add platform-specific fields
      if (platform == 'YouTube') {
        postData['youtube_video_id'] = workerId; // For YouTube, workerId is the video ID
        // Per YouTube, usa sempre il titolo personalizzato passato come parametro
        if (customTitle != null) {
          postData['title'] = customTitle;
        }
        if (customDescription != null) {
          postData['description'] = customDescription;
        } else {
          // Se non c'è descrizione personalizzata, non salvare quella globale
          // (l'utente ha disattivato il toggle)
          postData['description'] = null;
        }
      }
      
      await postRef.set(postData);
      
      // Salva anche le informazioni aggiuntive per le notifiche push
      await _saveNotificationData(
        userId: userId,
        uniquePostId: uniquePostId!,
        scheduledTime: scheduledDate,
        thumbnailUrl: thumbnailUrl,
        platform: platform,
        accountDisplayName: accountDisplayName,
      );
      
      print('✅ [FIREBASE_SAVE_INTERNAL] Post salvato con successo su Firebase:');
      print('✅ [FIREBASE_SAVE_INTERNAL] - Path: users/users/$userId/scheduled_posts/$uniquePostId');
      print('✅ [FIREBASE_SAVE_INTERNAL] - Unique Post ID: $uniquePostId');
      print('✅ [FIREBASE_SAVE_INTERNAL] - Worker ID: $workerId');
      print('✅ [FIREBASE_SAVE_INTERNAL] - Platform: $platform');
      
    } catch (e) {
      print('❌ [FIREBASE_SAVE_INTERNAL] Errore nel salvataggio su Firebase: $e');
      // We don't throw here to avoid affecting the user experience
      // The post is already scheduled in the worker
    }
  }
  
  // Nuovo metodo per salvare post multi-piattaforma
  Future<void> _saveMultiPlatformPostToFirebase(
    String userId,
    String text,
    DateTime scheduledDate,
    String? mediaUrl,
    String mediaType,
    String? thumbnailUrl,
    Map<String, Map<String, dynamic>> accountResults, // Map<uniqueKey, Map<accountId, resultData>>
    String? uniquePostId, // Aggiungo il parametro per l'ID univoco
    Map<String, int>? videoDuration, // Aggiungo il parametro per la durata del video
    List<String>? mediaUrls, // Aggiungo il parametro per la lista di media URLs (caroselli)
  ) async {
    try {
      print('Saving multi-platform post to Firebase with ${accountResults.length} accounts');
      print('🔄 [MULTI_PLATFORM_FIREBASE] ID univoco: $uniquePostId');
      
      final postRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(userId)
          .child('scheduled_posts')
          .child(uniquePostId!); // Usa l'ID univoco come chiave
      
      // Prepara i dati degli account per ogni piattaforma
      Map<String, dynamic> accountsData = {};
      
      // Itera su tutti i risultati degli account
      for (String uniqueKey in accountResults.keys) {
        final accountResult = accountResults[uniqueKey]!;
        final platform = accountResult['platform'] as String? ?? uniqueKey.split('_')[0];
        final accountId = accountResult['accountId'] as String;
        
        // Inizializza la struttura per la piattaforma se non esiste
        if (!accountsData.containsKey(platform)) {
          accountsData[platform] = {};
        }
        
        final workerId = accountResult['workerId'] as String;
        final accountUsername = accountResult['accountUsername'] as String?;
        final accountDisplayName = accountResult['accountDisplayName'] as String?;
        final accountProfileImageUrl = accountResult['accountProfileImageUrl'] as String?;
        
        // Ottieni descrizione e titolo personalizzati per questo account se disponibili
        String? customTitle;
        String? customDescription;
        
        // Usa la stessa logica di upload_confirmation_page.dart
        // Se c'è una descrizione personalizzata in platformDescriptions, usala
        // Altrimenti, usa la descrizione globale SOLO se l'utente non ha disattivato il toggle
        if (widget.platformDescriptions != null && 
            widget.platformDescriptions!.containsKey(platform) && 
            widget.platformDescriptions![platform]!.containsKey(accountId)) {
          final platformSpecificText = widget.platformDescriptions![platform]![accountId];
          if (platformSpecificText != null && platformSpecificText.isNotEmpty) {
            customDescription = platformSpecificText;
          }
          // Se la descrizione personalizzata è vuota, non usare quella globale
          // (l'utente ha disattivato il toggle e lasciato il campo vuoto)
        } else {
          // Se non c'è una chiave per questo account in platformDescriptions,
          // significa che l'utente ha disattivato il toggle per usare il contenuto globale
          // Non salvare nessuna descrizione
          customDescription = null;
        }
        
        // Per il titolo personalizzato, usa SOLO quello specifico per YouTube
        if (platform == 'YouTube' && widget.platformDescriptions != null &&
            widget.platformDescriptions!.containsKey('YouTube') &&
            widget.platformDescriptions!['YouTube']!.containsKey('${accountId}_title') &&
            widget.platformDescriptions!['YouTube']!['${accountId}_title']!.isNotEmpty) {
          customTitle = widget.platformDescriptions!['YouTube']!['${accountId}_title']!;
        }
        // fallback: nome file
        if ((customTitle == null || customTitle.isEmpty) && platform == 'YouTube' && _mediaFile != null) {
          customTitle = _mediaFile!.path.split('/').last;
        }
        
        // Genera una chiave unica per questo account (simile ai video pubblicati)
        final String uniqueAccountKey = _generateUniqueAccountKey(userId, platform, accountId);
        
        // Salva l'account con chiave unica invece di sovrascrivere
        accountsData[platform][uniqueAccountKey] = {
          'account_id': accountId,
          'worker_id': workerId,
          'account_username': accountUsername,
          'account_display_name': accountDisplayName,
          'account_profile_image_url': accountProfileImageUrl,
        };
        if (customTitle != null) {
          accountsData[platform][uniqueAccountKey]['title'] = customTitle;
        }
        if (customDescription != null) {
          accountsData[platform][uniqueAccountKey]['description'] = customDescription;
        }
        if (platform == 'YouTube') {
          accountsData[platform][uniqueAccountKey]['youtube_video_id'] = workerId;
        }
        
        print('✅ [MULTI_PLATFORM_FIREBASE] Account $accountId salvato per piattaforma $platform con chiave $uniqueAccountKey');
      }
      
      final postData = {
        'user_id': userId, // Aggiungo l'ID dell'utente attuale
        'text': text,
        'scheduled_time': scheduledDate.millisecondsSinceEpoch,
        'status': 'scheduled',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'thumbnail_url': thumbnailUrl,
        'is_multi_platform': true,
        'platforms_count': widget.selectedAccounts?.length ?? accountResults.length,
        'accounts': accountsData,
        'unique_post_id': uniquePostId, // Aggiungo l'ID univoco per il worker
      };
      
      // Aggiungi durata del video se disponibile
      if (videoDuration != null) {
        postData['video_duration_seconds'] = videoDuration['total_seconds'];
        postData['video_duration_minutes'] = videoDuration['minutes'];
        postData['video_duration_remaining_seconds'] = videoDuration['seconds'];
        print('🔥 [MULTI_PLATFORM_FIREBASE] Video duration added: ${videoDuration['total_seconds']} seconds');
      }
      
      // Aggiungi lista di media URLs se disponibile (per caroselli)
      if (mediaUrls != null && mediaUrls.isNotEmpty) {
        // Salva come oggetto con indici numerici per Firebase
        Map<String, String> mediaUrlsMap = {};
        for (int i = 0; i < mediaUrls.length; i++) {
          mediaUrlsMap[i.toString()] = mediaUrls[i];
        }
        postData['media_urls'] = mediaUrlsMap;
        print('📸 [MULTI_PLATFORM_FIREBASE] Media URLs salvati: ${mediaUrls.length} URL');
      }
      
      await postRef.set(postData);
      
      // Salva anche le informazioni aggiuntive per le notifiche push (multi-piattaforma)
      await _saveMultiPlatformNotificationData(
        userId: userId,
        uniquePostId: uniquePostId!,
        scheduledTime: scheduledDate,
        thumbnailUrl: thumbnailUrl,
        accountResults: accountResults,
      );
      
      print('Multi-platform post saved successfully with ${accountResults.length} accounts');
      print('✅ [MULTI_PLATFORM_FIREBASE] Post salvato con path: users/users/$userId/scheduled_posts/$uniquePostId');
    } catch (e) {
      print('Error saving multi-platform post to Firebase: $e');
      // We don't throw here to avoid affecting the user experience
      // The posts are already scheduled in the workers
    }
  }
  
  // Helper method to get content type based on file extension
  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      default:
        return 'application/octet-stream';
    }
  }
  
  // Helper method to upload media to Cloudflare R2
  Future<String> _uploadMediaToCloudflareR2(File file, String contentType) async {
    try {
      print('Inizio upload file su Cloudflare R2: ${file.path}');
      print('Dimensione file: ${await file.length()} bytes');
      
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      
      // Generate a unique filename
      final String extension = file.path.split('.').last.toLowerCase();
      final String fileName = 'media_${DateTime.now().millisecondsSinceEpoch}_${currentUser.uid}.$extension';
      final String fileKey = fileName;
      
      // Cloudflare R2 credentials - using correct credentials from storage.md
      final String accessKeyId = '5e181628bad7dc5481c92c6f3899efd6';
      final String secretKey = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
      final String endpoint = 'https://3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com';
      final String bucketName = 'videos';
      final String accountId = '3d945eb681944ec5965fecf275e41a9b';
      final String region = 'auto'; // R2 uses 'auto' as region
      
      // Get file bytes and size
      final bytes = await file.readAsBytes();
      final contentLength = bytes.length;
      
      // Calculate SHA-256 hash of content
      final List<int> contentHash = sha256.convert(bytes).bytes;
      final String payloadHash = hex.encode(contentHash);
      
      // Set up request information
      final String httpMethod = 'PUT';
      
      // SigV4 requires data in ISO8601 format
      final now = DateTime.now().toUtc();
      final String amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
      final String dateStamp = DateFormat("yyyyMMdd").format(now);
      
      // Host and URI
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
      
      // Sort headers lexicographically
      final sortedHeaderKeys = headers.keys.toList()..sort();
      for (final key in sortedHeaderKeys) {
        canonicalHeaders += '${key.toLowerCase()}:${headers[key]}\n';
        signedHeaders += '${key.toLowerCase()};';
      }
      signedHeaders = signedHeaders.substring(0, signedHeaders.length - 1); // Remove the last semicolon
      
      // Canonical request
      final String canonicalUri = '/$bucketName/$fileKey';
      final String canonicalQueryString = '';
      final String canonicalRequest = '$httpMethod\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
      
      // String to sign
      final String algorithm = 'AWS4-HMAC-SHA256';
      final String scope = '$dateStamp/$region/s3/aws4_request';
      final String stringToSign = '$algorithm\n$amzDate\n$scope\n${hex.encode(sha256.convert(utf8.encode(canonicalRequest)).bytes)}';
      
      // Sign
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
      
      // Setup progress tracking
      int bytesUploaded = 0;
      final streamedRequest = http.StreamedRequest(
        request.method,
        request.url,
      );
      
      // Add all headers to streamed request
      request.headers.forEach((key, value) {
        streamedRequest.headers[key] = value;
      });
      
      // Set up progress tracking as data is sent
      final progressStream = Stream<List<int>>.fromIterable(
        [bytes],
      ).transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            bytesUploaded += data.length;
            final progress = bytesUploaded / contentLength;
            print('Upload progress: ${(progress * 100).toInt()}%');
            sink.add(data);
          },
        ),
      );
      
      // Add the progress stream to the request
      await for (final chunk in progressStream) {
        streamedRequest.sink.add(chunk);
      }
      streamedRequest.sink.close();
      
      // Send the request and get the response
      final streamedResponse = await streamedRequest.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Generate public URL in the correct format
        // Use the format pub-[accountId].r2.dev
        final String publicUrl = 'https://pub-$accountId.r2.dev/$fileKey';
        
        print('File uploaded successfully to Cloudflare R2');
        print('Generated public URL: $publicUrl');
        
        // Verify that the URL is accessible
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
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appBlueColor = const Color(0xFF64B5F6);
    
    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      appBar: null,
      body: SafeArea(
        child: Column(
          children: [
            // Header from about_page.dart
            _buildHeader(context),
            
            // Main content
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : const Color(0xFFF8F8F8),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Scheduling containers (scrollable)
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Circular Scheduling Status moved to top
                            Center(child: _buildCircularSchedulingStatus(theme)),
                            SizedBox(height: 8),
                            SizedBox(height: 24),
                            
                            // Title and description removed as requested
                            
                            // Platform containers for selected accounts
                            _buildPlatformContainers(),
                            
                            SizedBox(height: 16),
                            
                            // Scheduling details card
                            // _buildSchedulingDetailsCard(),
                            
                            // SizedBox(height: 16),
                            
                            // Error message
                            if (_errorMessage != null && !_isLoading)
                              Container(
                                padding: EdgeInsets.all(16),
                                margin: EdgeInsets.only(bottom: 20),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            
                            // Manual retry button
                            if (!_isLoading && _selectedAccountId != null && _socialAccounts.isNotEmpty && _schedulingProgress < 100.0)
                              Container(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () => _schedulePost(),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(context).primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 2,
                                  ),
                                  child: Text(
                                    'Schedule Post',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            
                            // Show message if no accounts available
                            // Removed warning message
                          ],
                        ),
                      ),
                    ),
                    
                    // Collapsible tips section
                    _buildCollapsibleTips(appBlueColor),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _isLoading ? null : SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF667eea),
                  Color(0xFF764ba2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                transform: GradientRotation(135 * 3.14159 / 180),
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF667eea).withOpacity(0.3),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Chiudi il dialog
                // Naviga alla home page rimuovendo tutte le pagine precedenti dallo stack
                Navigator.pushNamedAndRemoveUntil(
                  context, 
                  '/', 
                  (route) => false
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                'Completed',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Build header like in about_page.dart
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
                      'Scheduling',
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

  // Build collapsible tips carousel widget with animation
  Widget _buildCollapsibleTips(Color appBlueColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isDark ? Colors.grey[850] : Colors.white,
      elevation: 4,
      shadowColor: Colors.black.withOpacity(isDark ? 0.18 : 0.1),
      child: InkWell(
        onTap: _toggleTipsVisibility,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tips header always visible
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  // App logo using actual app icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: appBlueColor.withOpacity(0.3),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/onboarding/circleICON.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback if asset not found
                          return CircleAvatar(
                            backgroundColor: appBlueColor,
                            radius: 16,
                            child: Text(
                              'V',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Scheduling Tips',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF2C2C3E),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Spacer(),
                  // Next tip button
                  if (_isTipsExpanded)
                    InkWell(
                      onTap: _nextTip,
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: appBlueColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.navigate_next,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  SizedBox(width: 8),
                  // Expand/collapse button with animation
                  AnimatedRotation(
                    turns: _isTipsExpanded ? 0.5 : 0.0,
                    duration: Duration(milliseconds: 300),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            
            // Tip content with animation
            AnimatedContainer(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _isTipsExpanded ? null : 0,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(),
              child: AnimatedOpacity(
                opacity: _isTipsExpanded ? 1.0 : 0.0,
                duration: Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: 500),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: Offset(0.1, 0.0),
                            end: Offset(0.0, 0.0),
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Row(
                      key: ValueKey<int>(_currentTipIndex),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: EdgeInsets.only(top: 4),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _getTipColor(_currentTipIndex),
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            viralTips[_currentTipIndex],
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF2C2C3E),
                              fontSize: 15,
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
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
      ),
    );
  }

  // Build circular scheduling status indicator
  Widget _buildCircularSchedulingStatus(ThemeData theme) {
    return Container(
      margin: EdgeInsets.only(top: 10, bottom: 25),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Circular progress indicator
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF6C63FF).withOpacity(0.2),
                  blurRadius: 15,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background circle
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[100],
                  ),
                ),
                
                // Custom circular progress indicator with gradient effect
                ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      colors: [
                                        Color(0xFF6C63FF), // Fluzar primary color
                Color(0xFFFF6B6B), // Fluzar secondary color
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds);
                  },
                  child: CustomPaint(
                    size: Size(220, 220),
                    painter: CircularProgressPainter(
                      progress: _schedulingProgress,
                      strokeWidth: 22,
                      color: Color(0xFF6C63FF),
                      smoothTransition: true,
                    ),
                  ),
                ),
                
                // White center
                Container(
                  width: 165,
                  height: 165,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return LinearGradient(
                              colors: [
                                Color(0xFF6C63FF),
                                Color(0xFFFF6B6B),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds);
                          },
                          child: Text(
                            '${_schedulingProgress.toInt()}%',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          _isLoading ? 'Scheduling...' : (_schedulingProgress >= 100.0 ? '' : 'Ready to schedule'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Status message
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              _schedulingStatus,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build scheduling details card
  Widget _buildSchedulingDetailsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  color: Color(0xFF6C63FF),
                  size: 24,
                ),
                SizedBox(width: 12),
                Text(
                  'Scheduling Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C2C3E),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            _buildInfoRow('Platform', widget.platform),
            Divider(height: 20),
            _buildInfoRow('Account', _getSelectedAccountName()),
            Divider(height: 20),
            _buildInfoRow('Date', _formatDateTime(_scheduledDate)),
            Divider(height: 20),
            _buildInfoRow('Content', _textController.text.isNotEmpty ? _textController.text : 'No text'),
            
            // Mostra informazioni sulle piattaforme multiple
            if (_hasMultiplePlatforms()) ...[
              Divider(height: 20),
              _buildInfoRow('Platforms', '${widget.selectedAccounts!.length} platforms selected'),
              Divider(height: 20),
              _buildInfoRow('Optimization', 'Single upload for all platforms'),
            ],
            
            if (_mediaFile != null || widget.cloudflareUrl != null) ...[
              Divider(height: 20),
              _buildInfoRow('Media', 'File attached'),
              if (widget.platform == 'Instagram') ...[
                Divider(height: 20),
                _buildInfoRow('Type', 'Reels'), // Instagram defaults to Reels for videos
              ],
              if (widget.platform == 'Threads') ...[
                Divider(height: 20),
                _buildInfoRow('Type', 'Post'), // Threads defaults to Post
              ],
              if (widget.platform == 'TikTok') ...[
                Divider(height: 20),
                _buildInfoRow('Type', 'Video'), // TikTok defaults to Video
              ],
            ],
          ],
        ),
      ),
    );
  }

  // Helper method to build info rows
  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: TextStyle(
              color: Colors.grey[900],
            ),
          ),
        ),
      ],
    );
  }

  // Helper method to format date and time
  String _formatDateTime(DateTime dateTime) {
    final DateFormat formatter = DateFormat('MMM d, y HH:mm');
    return formatter.format(dateTime);
  }

  // Helper method to get selected account name
  String _getSelectedAccountName() {
    if (_selectedAccountId != null && _socialAccounts.isNotEmpty) {
      final selectedAccount = _socialAccounts.firstWhere((account) => account['id'] == _selectedAccountId);
      return selectedAccount['username'] ?? 'Unknown account';
    }
    return 'No account selected';
  }

 
  void _showMultiPlatformPartialSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning icon with gradient background
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 15,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.warning_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              
              SizedBox(height: 24),
              
              // Title
              Text(
                'Partially Scheduled',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2C3E),
                ),
                textAlign: TextAlign.center,
              ),
              
              SizedBox(height: 12),
              
              // Subtitle
              Text(
                'Some posts were scheduled successfully, while others encountered issues',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              // Mostra la lista delle piattaforme fallite
              SizedBox(height: 16),
              if (_platformSchedulingStatus.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Not scheduled:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 6),
                    ..._platformSchedulingStatus.entries
                        .where((e) => e.value == false)
                        .map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 4.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.close, color: Colors.red, size: 18),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.key,
                                          style: TextStyle(
                                            color: Colors.red[800],
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        if (_platformErrors[e.key] != null && _platformErrors[e.key]!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2.0),
                                            child: Text(
                                              _platformErrors[e.key]!,
                                              style: TextStyle(
                                                color: Colors.grey[700],
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ],
              ),
              
              SizedBox(height: 32),
              
              // Action button
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Chiudi il dialog
                    // Naviga alla home page e pulisci lo stack di navigazione
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/home',
                      (route) => false, // Rimuovi tutte le route precedenti
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
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

  void _showMultiPlatformErrorDialog(String error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error icon with gradient background
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 15,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.error_outline,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              
              SizedBox(height: 24),
              
              // Title
              Text(
                'Scheduling Failed',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2C3E),
                ),
                textAlign: TextAlign.center,
              ),
              
              SizedBox(height: 12),
              
              // Subtitle
              Text(
                'An error occurred while scheduling your posts',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              
              SizedBox(height: 16),
              
              // Error details
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Text(
                  'Something went wrong while scheduling your posts. Please try again.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.red[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              SizedBox(height: 32),
              
              // Action button
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
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

  // Build platform containers for all selected accounts
  Widget _buildPlatformContainers() {
    if (widget.selectedAccounts == null || widget.selectedAccounts!.isEmpty) {
      return SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Platform sections
        ...widget.selectedAccounts!.entries.map((entry) {
          final platform = entry.key;
          final accountIds = entry.value;
          
          if (accountIds.isEmpty) return SizedBox.shrink();
          
          // Get account data for this platform
          List<Map<String, dynamic>> accounts = [];
          if (widget.socialAccounts != null && widget.socialAccounts!.containsKey(platform)) {
            accounts = widget.socialAccounts![platform]!
                .where((account) => accountIds.contains(account['id']))
                .toList();
          }
          
          if (accounts.isEmpty) return SizedBox.shrink();
          
          return _buildPlatformSection(platform, accounts);
        }).toList(),
      ],
    );
  }
  
  // Build a section for a specific platform with its accounts
  Widget _buildPlatformSection(String platform, List<Map<String, dynamic>> accounts) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    String logoPath = 'assets/loghi/logo_insta.png'; // Default
    
    // Set the correct logo path based on platform
    switch (platform) {
      case 'Instagram':
        logoPath = 'assets/loghi/logo_insta.png';
        break;
      case 'YouTube':
        logoPath = 'assets/loghi/logo_yt.png';
        break;
      case 'Twitter':
        logoPath = 'assets/loghi/logo_twitter.png';
        break;
      case 'Threads':
        logoPath = 'assets/loghi/threads_logo.png';
        break;
      case 'Facebook':
        logoPath = 'assets/loghi/logo_facebook.png';
        break;
      case 'TikTok':
        logoPath = 'assets/loghi/logo_tiktok.png';
        break;
    }
                  
    return Container(
      margin: EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Platform header with logo
          Row(
            children: [
              // Platform logo
              Container(
                width: 32,
                height: 32,
                margin: EdgeInsets.only(right: 12),
                child: Image.asset(
                  logoPath,
                  fit: BoxFit.contain,
                ),
              ),
              // Platform name
              Text(
                '$platform Accounts',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: isDark ? Colors.white : Color(0xFF2C2C3E),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          
          // Platform accounts container
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _platformColors[platform]!.withOpacity(isDark ? 0.08 : 0.15),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: _platformColors[platform]!.withOpacity(isDark ? 0.06 : 0.1),
                width: 1,
              ),
            ),
            child: Column(
              children: accounts.map((account) => 
                _buildAccountContainer(platform, account)
              ).toList(),
            ),
          ),
        ],
      ),
    );
  }
  
  // Build a single account container with improved minimal design
  Widget _buildAccountContainer(String platform, Map<String, dynamic> account) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accountId = account['id'] as String;
    
    // Per TikTok usa solo display_name, per le altre piattaforme usa la logica esistente
    final username = platform == 'TikTok' 
        ? (account['display_name'] ?? 'Account $accountId')
        : (account['username'] ?? account['name'] ?? account['display_name'] ?? 'Account $accountId');
    
    final platformColor = _platformColors[platform] ?? Colors.grey;
    
    // Get profile image if available
    String? profileImage;
    if (account.containsKey('profile_picture_url')) {
      profileImage = account['profile_picture_url'];
    } else if (account.containsKey('profile_image_url')) {
      profileImage = account['profile_image_url'];
    } else if (account.containsKey('avatar_url')) {
      profileImage = account['avatar_url'];
    } else if (account.containsKey('picture_url')) {
      profileImage = account['picture_url'];
    }
                  
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Profile image
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? platformColor.withOpacity(0.18) : platformColor.withOpacity(0.1),
                border: Border.all(
                  color: isDark ? platformColor.withOpacity(0.25) : platformColor.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: ClipOval(
                child: profileImage != null && profileImage.isNotEmpty
                    ? FadeInImage.assetNetwork(
                        placeholder: 'assets/loghi/logo_${platform.toLowerCase()}.png',
                        image: profileImage,
                        fit: BoxFit.cover,
                        imageErrorBuilder: (context, error, stackTrace) {
                          print('Error loading profile image for $platform: $error');
                          return Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: platformColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _getPlatformIcon(platform),
                              color: platformColor,
                              size: 20,
                            ),
                          );
                        },
                        placeholderErrorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: platformColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _getPlatformIcon(platform),
                              color: platformColor,
                              size: 20,
                            ),
                          );
                        },
                      )
                    : Image.asset(
                        'assets/loghi/logo_${platform.toLowerCase()}.png',
                        fit: BoxFit.contain,
                        width: 22,
                        height: 22,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            _getPlatformIcon(platform),
                            color: platformColor,
                            size: 20,
                          );
                        },
                      ),
              ),
            ),
            
            SizedBox(width: 14),
            
            // Account info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Username and status badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          platform == 'YouTube' ? username : '@$username',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isDark ? Colors.white : Color(0xFF2C2C3E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      
                      // Status badge
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? platformColor.withOpacity(0.22) : platformColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Ready',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: platformColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 6),
                  
                  // Status message
                  Text(
                    (_platformSchedulingStatus.containsKey(platform) && _platformSchedulingStatus[platform] == true)
                        ? 'Post scheduled successfully'
                        : 'Ready for scheduling',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Get icon for platform
  IconData _getPlatformIcon(String platform) {
    switch (platform) {
      case 'Instagram': return Icons.camera_alt;
      case 'YouTube': return Icons.play_arrow;
      case 'Twitter': return Icons.chat;
      case 'Threads': return Icons.tag;
      case 'Facebook': return Icons.facebook;
      case 'TikTok': return Icons.music_note;
      default: return Icons.public;
    }
  }

  // ... existing code ...
  Future<void> _deleteDraftIfNeeded() async {
    if (_draftId == null || _draftId!.isEmpty) return;
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .child(_draftId!)
          .remove();
      print('Draft deleted successfully with ID: $_draftId');
    } catch (e) {
      print('Error deleting draft: $e');
    }
  }

  // ... existing code ...
  // Dopo la schedulazione con successo, elimina la draft
  void _onSchedulingSuccess() {
    _deleteDraftIfNeeded();
    if (widget.onSchedulingComplete != null) {
      widget.onSchedulingComplete!();
    }
  }

  // ... cerca dove viene chiamato onSchedulingComplete e sostituisci con _onSchedulingSuccess ...

  // Metodo helper per generare ID univoci
  String _generateUniquePostId(String userId, String platform) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uniqueId = '${timestamp}_${userId}';
    
    print('🔍 [UNIQUE_ID] Generato ID univoco:');
    print('🔍 [UNIQUE_ID] - Timestamp: $timestamp');
    print('🔍 [UNIQUE_ID] - User ID: $userId');
    print('🔍 [UNIQUE_ID] - ID finale: $uniqueId');
    
    return uniqueId;
  }

  // Metodo helper per generare chiavi uniche per gli account
  String _generateUniqueAccountKey(String userId, String platform, String accountId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = math.Random().nextInt(1000);
    final uniqueKey = '-${timestamp}_${userId}_${platform}_${accountId}_$random';
    
    print('🔍 [UNIQUE_ACCOUNT_KEY] Generata chiave unica per account:');
    print('🔍 [UNIQUE_ACCOUNT_KEY] - Timestamp: $timestamp');
    print('🔍 [UNIQUE_ACCOUNT_KEY] - User ID: $userId');
    print('🔍 [UNIQUE_ACCOUNT_KEY] - Platform: $platform');
    print('🔍 [UNIQUE_ACCOUNT_KEY] - Account ID: $accountId');
    print('🔍 [UNIQUE_ACCOUNT_KEY] - Chiave finale: $uniqueKey');
    
    return uniqueKey;
  }

  // Function to get video duration in seconds and minutes
  Future<Map<String, int>?> _getVideoDuration() async {
    if (widget.videoFile == null) {
      return null; // Non serve se non c'è un video
    }
    
    try {
      final VideoPlayerController controller = VideoPlayerController.file(widget.videoFile!);
      await controller.initialize();
      
      final Duration duration = controller.value.duration;
      final int totalSeconds = duration.inSeconds;
      final int minutes = totalSeconds ~/ 60;
      final int seconds = totalSeconds % 60;
      
      await controller.dispose();
      
      return {
        'total_seconds': totalSeconds,
        'minutes': minutes,
        'seconds': seconds,
      };
    } catch (e) {
      print('Error getting video duration: $e');
      return null;
    }
  }

  /// Salva i dati per le notifiche push per post singoli
  Future<void> _saveNotificationData({
    required String userId,
    required String uniquePostId,
    required DateTime scheduledTime,
    String? thumbnailUrl,
    required String platform,
    String? accountDisplayName,
  }) async {
    try {
      final notificationRef = FirebaseDatabase.instance
          .ref()
          .child('scheduled_notifications')
          .child(uniquePostId);
      
      final notificationData = {
        'user_id': userId,
        'unique_post_id': uniquePostId,
        'scheduled_time': scheduledTime.millisecondsSinceEpoch,
        'thumbnail_url': thumbnailUrl,
        'platform': platform,
        'account_display_name': accountDisplayName,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'status': 'pending', // pending, sent, failed
      };
      
      await notificationRef.set(notificationData);
      
      print('✅ [NOTIFICATION_DATA] Dati notifica salvati:');
      print('✅ [NOTIFICATION_DATA] - Path: scheduled_notifications/$uniquePostId');
      print('✅ [NOTIFICATION_DATA] - Platform: $platform');
      print('✅ [NOTIFICATION_DATA] - Scheduled Time: ${scheduledTime.toIso8601String()}');
      
    } catch (e) {
      print('❌ [NOTIFICATION_DATA] Errore nel salvataggio dati notifica: $e');
      // Non lanciare l'errore per non influenzare l'esperienza utente
    }
  }

  /// Salva i dati per le notifiche push per post multi-piattaforma
  Future<void> _saveMultiPlatformNotificationData({
    required String userId,
    required String uniquePostId,
    required DateTime scheduledTime,
    String? thumbnailUrl,
    required Map<String, Map<String, dynamic>> accountResults,
  }) async {
    try {
      final notificationRef = FirebaseDatabase.instance
          .ref()
          .child('scheduled_notifications')
          .child(uniquePostId);
      
      // Prepara i dati delle piattaforme
      Map<String, dynamic> platformsData = {};
      List<String> platformNames = [];
      List<String> accountDisplayNames = [];
      
      for (String uniqueKey in accountResults.keys) {
        final accountResult = accountResults[uniqueKey]!;
        final platform = accountResult['platform'] as String? ?? uniqueKey.split('_')[0];
        final accountDisplayName = accountResult['accountDisplayName'] as String?;
        
        // Inizializza la piattaforma se non esiste
        if (!platformsData.containsKey(platform)) {
          platformsData[platform] = {
            'account_display_names': <String>[],
          };
          platformNames.add(platform);
        }
        
        // Aggiungi il nome dell'account alla lista
        if (accountDisplayName != null) {
          (platformsData[platform]['account_display_names'] as List<String>).add(accountDisplayName);
          accountDisplayNames.add(accountDisplayName);
        }
      }
      
      final notificationData = {
        'user_id': userId,
        'unique_post_id': uniquePostId,
        'scheduled_time': scheduledTime.millisecondsSinceEpoch,
        'thumbnail_url': thumbnailUrl,
        'platforms': platformsData,
        'platform_names': platformNames,
        'account_display_names': accountDisplayNames,
        'is_multi_platform': true,
        'platforms_count': platformNames.length,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'status': 'pending', // pending, sent, failed
      };
      
      await notificationRef.set(notificationData);
      
      print('✅ [MULTI_NOTIFICATION_DATA] Dati notifica multi-piattaforma salvati:');
      print('✅ [MULTI_NOTIFICATION_DATA] - Path: scheduled_notifications/$uniquePostId');
      print('✅ [MULTI_NOTIFICATION_DATA] - Platforms: ${platformNames.join(', ')}');
      print('✅ [MULTI_NOTIFICATION_DATA] - Scheduled Time: ${scheduledTime.toIso8601String()}');
      
    } catch (e) {
      print('❌ [MULTI_NOTIFICATION_DATA] Errore nel salvataggio dati notifica: $e');
      // Non lanciare l'errore per non influenzare l'esperienza utente
    }
  }
}
