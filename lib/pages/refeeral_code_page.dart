import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter

class ReferralCodePage extends StatefulWidget {
  const ReferralCodePage({super.key});

  @override
  State<ReferralCodePage> createState() => _ReferralCodePageState();
}

class _ReferralCodePageState extends State<ReferralCodePage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  
  // Referral code related variables
  String? _referralCode;
  int _referredUsersCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserReferralData();
  }

  // Load user's referral code and referred users count
  Future<void> _loadUserReferralData() async {
    if (_currentUser == null || !mounted) return;
    
    try {
      final userRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid);
      
      final snapshot = await userRef.get();
      
      if (!mounted) return;
      
      if (snapshot.exists && snapshot.value is Map) {
        final userData = snapshot.value as Map<dynamic, dynamic>;
        
        // Get referral code
        if (userData.containsKey('referral_code')) {
          setState(() {
            _referralCode = userData['referral_code'] as String?;
          });
        }
        
        // Get referred users count - prioritize the referral_count field if available
        if (userData.containsKey('referral_count')) {
          setState(() {
            _referredUsersCount = userData['referral_count'] as int? ?? 0;
          });
        } else if (userData.containsKey('referred_users')) {
          // Fall back to counting the referred_users list if referral_count is not available
          if (userData['referred_users'] is List) {
            setState(() {
              _referredUsersCount = (userData['referred_users'] as List).length;
            });
          } else if (userData['referred_users'] is Map) {
            // Firebase sometimes stores lists as maps with numeric keys
            final Map<dynamic, dynamic> referredUsersMap = userData['referred_users'] as Map<dynamic, dynamic>;
            setState(() {
              _referredUsersCount = referredUsersMap.length;
            });
          }
        }
      }
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading user referral data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Share referral code using system share sheet
  Future<void> _shareReferralCode() async {
    if (_referralCode == null) return;
    
    try {
      final String message = 'Hey! Join me on Fluzar and get 500 bonus credits! Use my referral code: $_referralCode';
      
      await Share.share(
        message,
        subject: 'Join Fluzar with my referral code',
      );
    } catch (e) {
      print('Error sharing referral code: $e');
      // Fallback to clipboard
      await Clipboard.setData(ClipboardData(text: _referralCode!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Referral code copied to clipboard: $_referralCode'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Copy referral code to clipboard
  Future<void> _copyReferralCode() async {
    if (_referralCode == null) return;
    
    try {
      await Clipboard.setData(ClipboardData(text: _referralCode!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text(
                  'Referral code copied: $_referralCode',
                  style: TextStyle(color: Colors.black87),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error copying referral code: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error copying referral code'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
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
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        appBar: null,
        body: Stack(
          children: [
            // Main content area - no padding, content can scroll behind floating header
            SafeArea(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _referralCode == null
                      ? _buildNoReferralCodeState(theme)
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 100, 24, 24), // Aggiunto padding superiore per la top bar
                          child: Column(
                            children: [
                              _buildReferralCodeCard(theme),
                              const SizedBox(height: 24),
                              _buildReferralProgressList(theme),
                              const SizedBox(height: 24),
                              _buildHowItWorksSection(theme),
                            ],
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
                  borderRadius: BorderRadius.circular(20),
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
                    'Referral',
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

  Widget _buildNoReferralCodeState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.code_off,
            size: 64,
            color: theme.brightness == Brightness.dark ? Color(0xFF667eea) : Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            'No referral code available',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Your referral code will be generated soon',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Build the referral code card
  Widget _buildReferralCodeCard(ThemeData theme) {
    if (_referralCode == null) return const SizedBox.shrink();
    
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            // Effetto vetro semi-trasparente opaco
            color: isDark 
                ? Colors.white.withOpacity(0.15) 
                : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(20),
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
          padding: const EdgeInsets.all(20),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your Referral Code',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.titleLarge?.color,
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
                  child: Text(
                    '$_referredUsersCount Uses',
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
          const SizedBox(height: 20),
          
          // Referral code display
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Color(0xFF667eea).withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _copyReferralCode,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.outline,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
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
                                    _referralCode!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
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
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF667eea).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _shareReferralCode,
                      borderRadius: BorderRadius.circular(7),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
                        child: Icon(
                          Icons.share,
                          color: Colors.white,
                          size: 18,
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
  }

  // Build the referral progress list similar to Getting Started
  Widget _buildReferralProgressList(ThemeData theme) {
    // Define the referral steps
    final List<Map<String, dynamic>> referralSteps = [
      {
        'number': 1,
        'title': '1st Friend',
        'description': 'Invite your first friend and earn 1000 credits',
        'isCompleted': _referredUsersCount >= 1,
        'credits': 1000,
        'icon': Icons.person_add,
      },
      {
        'number': 2,
        'title': '2nd Friend',
        'description': 'Invite your second friend and earn 1500 credits',
        'isCompleted': _referredUsersCount >= 2,
        'credits': 1500,
        'icon': Icons.people_outline,
      },
      {
        'number': 3,
        'title': '3rd Friend',
        'description': 'Invite your third friend and earn 3000 credits',
        'isCompleted': _referredUsersCount >= 3,
        'credits': 3000,
        'icon': Icons.groups,
      },
      {
        'number': 4,
        'title': '4+ Friends',
        'description': 'Invite more friends and earn 1000 credits each',
        'isCompleted': _referredUsersCount >= 4,
        'credits': 1000,
        'icon': Icons.add_circle_outline,
        'isRepeating': true,
      },
    ];

    // Calculate current progress
    int completedSteps = referralSteps.where((step) => step['isCompleted'] as bool).length;
    int totalSteps = referralSteps.length;
    int currentStep = completedSteps < totalSteps ? completedSteps + 1 : totalSteps;
    
    // Build the step widgets
    List<Widget> stepWidgets = [];
    
    // Add a top decoration for the first step
    stepWidgets.add(
      Container(
        margin: EdgeInsets.only(left: 22.5),
        width: 3,
        height: 15,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              referralSteps[0]['isCompleted'] as bool 
                  ? Color(0xFF667eea) 
                  : Colors.grey.shade300,
              referralSteps[0]['isCompleted'] as bool 
                  ? Color(0xFF764ba2) 
                  : Colors.grey.shade300,
            ],
            transform: GradientRotation(135 * 3.14159 / 180),
          ),
        ),
      ),
    );
    
    for (int i = 0; i < referralSteps.length; i++) {
      final step = referralSteps[i];
      final isActive = (i + 1) <= currentStep;
      final isCompleted = step['isCompleted'] as bool;
      
      // Add the step item
      stepWidgets.add(
        _buildReferralStepItem(
          theme,
          number: step['number'] as int,
          title: step['title'] as String,
          description: step['description'] as String,
          credits: step['credits'] as int,
          isActive: isActive,
          isCompleted: isCompleted,
          icon: step['icon'] as IconData,
          isRepeating: step['isRepeating'] as bool? ?? false,
        ),
      );
      
      // Add connecting line (don't show after last item)
      if (i < referralSteps.length - 1) {
        stepWidgets.add(
          Container(
            margin: EdgeInsets.only(left: 22.5),
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  isCompleted ? Color(0xFF667eea) : Colors.grey.shade300,
                  i + 1 < currentStep 
                      ? Color(0xFF764ba2) 
                      : Colors.grey.shade300,
                ],
                transform: GradientRotation(135 * 3.14159 / 180),
              ),
            ),
          ),
        );
      } else {
        // For the last item, add a bottom decoration to complete the visual
        stepWidgets.add(
          Container(
            margin: EdgeInsets.only(left: 22.5),
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  isCompleted ? Color(0xFF667eea) : Colors.grey.shade300,
                  isCompleted ? Color(0xFF764ba2) : Colors.grey.shade300,
                ],
                transform: GradientRotation(135 * 3.14159 / 180),
              ),
            ),
          ),
        );
      }
    }
    
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
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
                  'Referral Progress',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
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
                  child: Text(
                    '$completedSteps/$totalSteps Steps',
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
          const SizedBox(height: 20),
          // Add all the step widgets
          ...stepWidgets,
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildReferralStepItem(
    ThemeData theme, {
    required int number,
    required String title,
    required String description,
    required int credits,
    required bool isActive,
    required bool isCompleted,
    required IconData icon,
    required bool isRepeating,
  }) {
    final Color accentColor = isCompleted 
        ? Color(0xFF667eea)
        : isActive 
            ? Color(0xFF667eea)
            : Colors.grey.shade400;
            
    final Color backgroundColor = isCompleted 
        ? Color(0xFF667eea).withOpacity(0.1)
        : isActive 
            ? Color(0xFF667eea).withOpacity(0.05)
            : theme.colorScheme.surfaceVariant;
            
    if (!isActive && !isCompleted) {
      // Non iniziato: applica effetto glass con bordo visibile
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            margin: EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.12)
                  : Colors.white.withOpacity(0.22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.28)
                    : Colors.white.withOpacity(0.55),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.brightness == Brightness.dark
                      ? Colors.black.withOpacity(0.08)
                      : Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step number/check circle
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.0),
                    border: Border.all(
                      color: theme.brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.45)
                          : Colors.grey.shade400,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      isRepeating ? '4+' : number.toString(),
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Content
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
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade500,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          // Credits badge
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.0),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.brightness == Brightness.dark
                                    ? Colors.white.withOpacity(0.35)
                                    : Colors.grey.shade300,
                                width: 1,
                              ),
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
                                '+$credits',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Step icon
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.0),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.brightness == Brightness.dark
                                    ? Colors.white.withOpacity(0.4)
                                    : Colors.grey.shade400,
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              icon,
                              color: Colors.grey.shade500,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
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
    }
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      margin: EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? theme.cardColor : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: (isActive || isCompleted)
            ? Border.all(
                color: Color(0xFF667eea).withOpacity(0.6), 
                width: 2
              )
            : null,
        boxShadow: (isActive || isCompleted)
            ? [
                BoxShadow(
                  color: Color(0xFF667eea).withOpacity(0.15),
                  blurRadius: 12,
                  spreadRadius: 1,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number/check circle
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: (isActive || isCompleted)
                  ? LinearGradient(
                      colors: [
                        Color(0xFF667eea),
                        Color(0xFF764ba2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      transform: GradientRotation(135 * 3.14159 / 180),
                    )
                  : null,
              color: (isActive || isCompleted) ? null : backgroundColor,
              border: Border.all(
                color: accentColor,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF667eea).withOpacity(0.3),
                  blurRadius: 12,
                  spreadRadius: 3,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: isCompleted
                  ? Icon(
                      Icons.check,
                      color: (isActive || isCompleted) ? Colors.white : accentColor,
                      size: 22,
                    )
                  : Text(
                      isRepeating ? '4+' : number.toString(),
                      style: TextStyle(
                        color: (isActive || isCompleted) ? Colors.white : accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          
          // Content
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
                          fontWeight: FontWeight.bold,
                          color: isActive ? theme.textTheme.bodyLarge?.color : Colors.grey.shade500,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    // Credits badge
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: (isCompleted || isActive)
                            ? LinearGradient(
                                colors: [
                                  Color(0xFF667eea).withOpacity(0.1),
                                  Color(0xFF764ba2).withOpacity(0.1),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                transform: GradientRotation(135 * 3.14159 / 180),
                              )
                            : null,
                        color: (isCompleted || isActive) ? null : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (isCompleted || isActive) ? Color(0xFF667eea) : Colors.grey.shade300,
                          width: 1,
                        ),
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
                          '+$credits',
                          style: TextStyle(
                            color: (isCompleted || isActive) ? Colors.white : Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Step icon
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: (isActive || isCompleted)
                            ? LinearGradient(
                                colors: [
                                  Color(0xFF667eea),
                                  Color(0xFF764ba2),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                transform: GradientRotation(135 * 3.14159 / 180),
                              )
                            : null,
                        color: (isActive || isCompleted) ? null : backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        color: (isActive || isCompleted) ? Colors.white : accentColor,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: isActive ? Colors.grey.shade600 : Colors.grey.shade400,
                    fontSize: 14,
                  ),
                ),
                if (isActive && !isCompleted) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _shareReferralCode,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
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
                          borderRadius: BorderRadius.circular(12),
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
                            'Share your code',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (isCompleted) ...[
                  const SizedBox(height: 8),
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
                        child: Icon(
                          Icons.check_circle_outline,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                      SizedBox(width: 6),
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
                          'Completed',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build the how it works section
  Widget _buildHowItWorksSection(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
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
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              'How it works',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // Horizontal steps
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildHowItWorksStep(
                theme,
                icon: Icons.share,
                title: 'Share',
                description: 'Your code with anyone',
              ),
              _buildStepConnector(theme),
              _buildHowItWorksStep(
                theme,
                icon: Icons.person_add,
                title: 'Register',
                description: 'Using your code',
              ),
              _buildStepConnector(theme),
              _buildHowItWorksStep(
                theme,
                icon: Icons.star,
                title: 'Earn',
                description: 'Both get rewards',
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Bonus info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF667eea).withOpacity(0.15),
                  Color(0xFF764ba2).withOpacity(0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                transform: GradientRotation(135 * 3.14159 / 180),
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Color(0xFF667eea).withOpacity(0.3),
                width: 1,
              ),
            ),
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
                    Icons.lightbulb_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your friends get +500 bonus credits when they sign up with your code!',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.brightness == Brightness.dark 
                          ? Colors.white.withOpacity(0.9) 
                          : Color(0xFF667eea),
                      fontWeight: FontWeight.w500,
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
  }
  
  // Helper widget for how it works step
  Widget _buildHowItWorksStep(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark 
              ? Color(0xFF2A2A2A) 
              : theme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.brightness == Brightness.dark 
                ? Colors.grey.shade700 
                : Color(0xFF667eea).withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF667eea).withOpacity(0.2),
                    Color(0xFF764ba2).withOpacity(0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  transform: GradientRotation(135 * 3.14159 / 180),
                ),
                shape: BoxShape.circle,
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
                  icon,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.brightness == Brightness.dark 
                    ? Colors.white 
                    : theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: theme.brightness == Brightness.dark 
                    ? Color(0xFF667eea)
                    : theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Helper widget for step connector
  Widget _buildStepConnector(ThemeData theme) {
    return Container(
      width: 20,
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
          child: Icon(
            Icons.arrow_forward,
            color: Colors.white,
            size: 16,
          ),
        ),
      ),
    );
  }
}
