import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'dart:math' as math;
import 'dart:async';
import '../main.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> with TickerProviderStateMixin {
  late ScrollController _scrollController;
  late PageController _horizontalScrollController;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late AnimationController _parallaxController;
  
  double _scrollOffset = 0.0;
  double _parallaxOffset = 0.0;
  int _currentSection = 0;
  int _currentPage = 0;
  
  // Feature list animation
  int _visibleFeatures = 0;
  late Timer _featureTimer;
  
  // Progress number animation
  int _displayedProgress = 0;
  late AnimationController _progressNumberController;
  late Animation<double> _progressNumberAnimation;
  
  // Progress bar animation
  double _animatedProgressWidth = 0.0;
  
  // Get Started button animation
  bool _showGetStartedButton = false;
  bool _hasSeenSection3 = false;
  
  // Get Started button slide animation
  late AnimationController _getStartedButtonController;
  late Animation<Offset> _getStartedButtonSlideAnimation;
  
  // Animation values
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _parallaxAnimation;

  @override
  void initState() {
    super.initState();
    
    _scrollController = ScrollController();
    _horizontalScrollController = PageController();
    _fadeController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _slideController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _scaleController = AnimationController(duration: const Duration(milliseconds: 900), vsync: this);
    _parallaxController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _progressNumberController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this);
    _getStartedButtonController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic)
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic)
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut)
    );
    _parallaxAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _parallaxController, curve: Curves.easeOut)
    );
    _progressNumberAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressNumberController, curve: Curves.easeOutCubic)
    );
    _getStartedButtonSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1), // Parte dal basso
      end: Offset.zero, // Arriva alla posizione finale
    ).animate(CurvedAnimation(
      parent: _getStartedButtonController,
      curve: Curves.easeOutCubic,
    ));
    
    _horizontalScrollController.addListener(_onPageChanged);
    
    // Listener per aggiornare il valore visualizzato durante l'animazione del numero
    _progressNumberAnimation.addListener(() {
      setState(() {
        _displayedProgress = _progressNumberAnimation.value.round();
        _animatedProgressWidth = _progressNumberAnimation.value / 100.0;
      });
    });
    
    // Start initial animations with staggered timing
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 400), () => _slideController.forward());
    Future.delayed(const Duration(milliseconds: 800), () => _scaleController.forward());
    Future.delayed(const Duration(milliseconds: 1200), () => _parallaxController.forward());
    
    // Initialize progress number at 0
    _displayedProgress = 0;
    _animatedProgressWidth = 0.0;
    
    // Start progress animation to 33% after 1 second
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _startInitialProgressAnimation();
      }
    });
    
    // Start feature animation for first card
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _startFeatureAnimation();
      }
    });
  }

  void _onScroll() {
    // Scroll functionality removed - animations will start automatically
        setState(() {
      _scrollOffset = 0.0;
      _parallaxOffset = 0.0;
      _currentSection = 0;
    });
  }

  void _onPageChanged() {
    if (_horizontalScrollController.page != null) {
      setState(() {
        _currentPage = _horizontalScrollController.page!.round();
      });
      
      // Start progress number animation
      _startProgressNumberAnimation();
      
      // Start feature animation for any visible card
      _startFeatureAnimation();
      
      // Check if we're viewing section 3 for the first time
      if (_currentPage == 2 && !_hasSeenSection3) {
        _hasSeenSection3 = true;
        // Show Get Started button after 2.5 seconds of viewing section 3
        Future.delayed(const Duration(milliseconds: 2300), () {
          if (mounted) {
            setState(() {
              _showGetStartedButton = true;
            });
            // Start the slide-up animation
            _getStartedButtonController.forward();
          }
        });
      }
    }
  }
  
  void _startProgressNumberAnimation() {
    final totalPages = 3;
    final currentProgress = (_currentPage + 1) / totalPages;
    final targetProgress = (currentProgress * 100).round();
    
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

  void _startInitialProgressAnimation() {
    final targetProgress = 33;
    _progressNumberAnimation = Tween<double>(
      begin: _displayedProgress.toDouble(),
      end: targetProgress.toDouble(),
    ).animate(CurvedAnimation(
      parent: _progressNumberController,
      curve: Curves.easeOutCubic,
    ));
    _progressNumberController.forward(from: 0);
  }
  
  void _startFeatureAnimation() {
    _stopFeatureAnimation(); // Stop any existing timer
    setState(() {
      _visibleFeatures = 0;
    });
    
    // Initial delay before starting the staggered animation
    Future.delayed(Duration(milliseconds: 500), () {
      if (mounted) {
        // Staggered animation: each feature appears with different timing
        Future.delayed(Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              _visibleFeatures = 1;
            });
          }
        });
        
        Future.delayed(Duration(milliseconds: 800), () {
          if (mounted) {
            setState(() {
              _visibleFeatures = 2;
            });
          }
        });
        
        Future.delayed(Duration(milliseconds: 1300), () {
          if (mounted) {
            setState(() {
              _visibleFeatures = 3;
            });
          }
        });
      }
    });
  }
  
  void _stopFeatureAnimation() {
    try {
      _featureTimer.cancel();
    } catch (e) {
      // Timer not initialized yet
    }
    setState(() {
      _visibleFeatures = 0;
    });
  }

  @override
  void dispose() {
    _stopFeatureAnimation();
    _horizontalScrollController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _parallaxController.dispose();
    _progressNumberController.dispose();
    _getStartedButtonController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const AuthPage(initialMode: false),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? Color(0xFF121212) : Colors.white,
      body: Stack(
        children: [
          // Animated Background with multiple layers
          _buildAnimatedBackground(),
          
          // Floating Particles with physics
          ...List.generate(30, (index) => _buildFloatingParticle(index)),
          
          // Main Content
          _buildIntuitiveInterfaceSection(),
          
          // Progress Indicator
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 0),
              child: _buildProgressIndicator(),
            ),
          ),
          
          // Navigation button for sections 1 and 2 (fixed at bottom)
          if (!_showGetStartedButton && _currentPage < 2)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 280,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF667eea), // Blu violaceo al 0%
                        Color(0xFF764ba2), // Viola al 100%
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF667eea).withOpacity(0.3),
                        blurRadius: 15,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () {
                        // Navigate to next page
                        _horizontalScrollController.nextPage(
                          duration: Duration(milliseconds: 500),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Center(
                        child: Text(
                          'Next',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontFamily: 'Ethnocentric',
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Stack(
                          children: [
        // Base gradient layer
                            Positioned(
          top: -_parallaxOffset * 0.3,
                              left: 0,
                              right: 0,
                              child: Container(
            height: MediaQuery.of(context).size.height * 2,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: isDark ? [
                  Colors.purple.withOpacity(0.15),
                  Colors.blue.withOpacity(0.08),
                  Colors.transparent,
                  Colors.purple.withOpacity(0.12),
                  Colors.blue.withOpacity(0.06),
                ] : [
                  Color(0xFF667eea).withOpacity(0.08),
                  Color(0xFF764ba2).withOpacity(0.05),
                  Colors.transparent,
                  Color(0xFF667eea).withOpacity(0.06),
                  Color(0xFF764ba2).withOpacity(0.03),
                ],
                stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                                  ),
                                ),
                              ),
                            ),
        
        // Animated geometric shapes
        ...List.generate(8, (index) => _buildGeometricShape(index)),
      ],
    );
  }

  Widget _buildGeometricShape(int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final random = math.Random(index);
    final size = random.nextDouble() * 100 + 50;
    final opacity = random.nextDouble() * 0.1 + 0.05;
    final color = isDark 
        ? (index % 2 == 0 ? Colors.purple : Colors.blue)
        : (index % 2 == 0 ? Color(0xFF667eea) : Color(0xFF764ba2));
    final speed = random.nextDouble() * 0.3 + 0.1;
    
    return Positioned(
      left: random.nextDouble() * MediaQuery.of(context).size.width,
      top: random.nextDouble() * MediaQuery.of(context).size.height * 2,
      child: AnimatedBuilder(
        animation: _parallaxController,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, -_parallaxOffset * speed),
            child: Transform.rotate(
              angle: _parallaxOffset * 0.002 * (index + 1),
                              child: Container(
                width: size,
                height: size,
                                decoration: BoxDecoration(
                  color: color.withOpacity(opacity),
                  shape: index % 3 == 0 ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: index % 3 == 0 ? null : BorderRadius.circular(20),
                                  ),
                                ),
                              ),
          );
        },
      ),
    );
  }

  Widget _buildFloatingParticle(int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final random = math.Random(index);
    final size = random.nextDouble() * 6 + 3;
    final speed = random.nextDouble() * 0.5 + 0.1;
    
    return Positioned(
      left: random.nextDouble() * MediaQuery.of(context).size.width,
      top: random.nextDouble() * MediaQuery.of(context).size.height * 2,
      child: AnimatedBuilder(
        animation: _parallaxController,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, -_parallaxOffset * speed),
            child: Container(
              width: size,
              height: size,
                              decoration: BoxDecoration(
                color: isDark 
                    ? Colors.purple.withOpacity(0.4)
                    : Color(0xFF667eea).withOpacity(0.3),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: isDark 
                        ? Colors.purple.withOpacity(0.6)
                        : Color(0xFF667eea).withOpacity(0.4),
                    blurRadius: 15,
                    spreadRadius: 3,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIntuitiveInterfaceSection() {
    return Container(
      padding: const EdgeInsets.only(top: 140, bottom: 20, left: 20, right: 20),
      child: Column(
        children: [

          
          // Horizontal Scrollable Cards
          Container(
            height: 560,
            margin: EdgeInsets.only(top: 0),
            padding: EdgeInsets.only(bottom: 20),
            child: PageView(
              controller: _horizontalScrollController,
              physics: const PageScrollPhysics(),
              children: [
                Center(
                  child: _buildHorizontalCard(
                    imagePath: 'assets/onboarding/2.png',
                    title: 'FLUZAR',
                    description: 'FEATURE_LIST',
                    index: 0,
                  ),
                ),
                Center(
                  child: _buildHorizontalCard(
                    imagePath: 'assets/onboarding/1.png',
                    title: 'One click, thousand destinations',
                    description: 'FEATURE_LIST_2',
                    index: 1,
                  ),
                ),
                Center(
                  child: _buildHorizontalCard(
                    imagePath: 'assets/onboarding/3.png',
                    title: 'Intelligence that works for you',
                    description: 'FEATURE_LIST_3',
                    index: 2,
                  ),
                ),
              ],
            ),
          ),
          
          // Get Started button positioned below cards in section 3
          if (_showGetStartedButton)
            SlideTransition(
              position: _getStartedButtonSlideAnimation,
              child: Container(
                width: 280,
                height: 56,
                margin: EdgeInsets.only(top: 25), // Aumentato il margine superiore per spostare il pulsante più in basso
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea), // Blu violaceo al 0%
                      Color(0xFF764ba2), // Viola al 100%
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 15,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AuthPage(initialMode: false),
                        ),
                      );
                    },
                    child: Center(
                      child: Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Ethnocentric',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          
          SizedBox(height: 8),
          

        ],
      ),
    );
  }

  Widget _buildHorizontalCard({
    required String imagePath,
    required String title,
    required String description,
    required int index,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 800 + (index * 200)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.8 + (0.2 * value),
          child: Opacity(
            opacity: value,
            child: Container(
              width: 320,
              decoration: BoxDecoration(
                color: isDark 
                    ? Colors.white.withOpacity(0.08)
                    : Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: isDark 
                      ? Colors.purple.withOpacity(0.3 * value)
                      : Color(0xFF667eea).withOpacity(0.2 * value),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark 
                        ? Colors.purple.withOpacity(0.15 * value)
                        : Color(0xFF667eea).withOpacity(0.1 * value),
                    blurRadius: 25,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Animation or image section
                  Container(
                    width: double.infinity,
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                      boxShadow: [
                        BoxShadow(
                          color: isDark 
                              ? Colors.purple.withOpacity(0.2 * value)
                              : Color(0xFF667eea).withOpacity(0.1 * value),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                        BoxShadow(
                          color: isDark 
                              ? Colors.purple.withOpacity(0.1 * value)
                              : Color(0xFF667eea).withOpacity(0.05 * value),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                      child: index == 0
                                                                ? Center(
                                            child: Lottie.asset(
                                              'assets/animations/marketing.json',
                                              width: 180,
                                              height: 180,
                                              fit: BoxFit.contain,
                                            ),
                                          )
                        : index == 1
                        ? Center(
                            child: Lottie.asset(
                              'assets/animations/social_share.json',
                              width: 180,
                              height: 180,
                              fit: BoxFit.contain,
                            ),
                          )
                                                                  : Center(
                                              child: Lottie.asset(
                                                'assets/animations/analytics.json',
                                                width: 180,
                                                height: 180,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                    ),
                  ),
                  
                  // Content Section for all cards
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14, // Ridotto da 24 a 20 per titoli più compatti
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                            fontFamily: 'Ethnocentric',
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        // Feature list for all cards
                        if (description == 'FEATURE_LIST')
                          Column(
                            children: [
                              if (_visibleFeatures > 0) _buildFeatureCard('All your social media in one place', 0),
                              if (_visibleFeatures > 0) SizedBox(height: 12),
                              if (_visibleFeatures > 1) _buildFeatureCard('A simple and intuitive flow', 1),
                              if (_visibleFeatures > 1) SizedBox(height: 12),
                              if (_visibleFeatures > 2) _buildFeatureCard('More time to create, less to manage', 2),
                            ],
                          )
                        else if (description == 'FEATURE_LIST_2')
                          Column(
                            children: [
                              if (_visibleFeatures > 0) _buildFeatureCard('Multi-platform sharing in real time', 0),
                              if (_visibleFeatures > 0) SizedBox(height: 12),
                              if (_visibleFeatures > 1) _buildFeatureCard('Intelligent scheduling for your posts', 1),
                              if (_visibleFeatures > 1) SizedBox(height: 12),
                              if (_visibleFeatures > 2) _buildFeatureCard('Everything in one click', 2),
                            ],
                          )
                        else if (description == 'FEATURE_LIST_3')
                          Column(
                            children: [
                              if (_visibleFeatures > 0) _buildFeatureCard('AI analysis of your content', 0),
                              if (_visibleFeatures > 0) SizedBox(height: 12),
                              if (_visibleFeatures > 1) _buildFeatureCard('AI-powered trend suggestions', 1),
                              if (_visibleFeatures > 1) SizedBox(height: 12),
                              if (_visibleFeatures > 2) _buildFeatureCard('Clear reports to grow faster', 2),
                            ],
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
  }

  Widget _buildFeatureCard(String text, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 600),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 20),
          child: Opacity(
            opacity: value,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark 
                    ? Colors.white.withOpacity(0.03)
                    : Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark 
                      ? Colors.white.withOpacity(0.08)
                      : Color(0xFF667eea).withOpacity(0.1),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark 
                        ? Colors.black.withOpacity(0.1)
                        : Color(0xFF667eea).withOpacity(0.05),
                    blurRadius: 6,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Icon indicator with subtle gradient
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF667eea).withOpacity(0.8),
                          Color(0xFF764ba2).withOpacity(0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF667eea).withOpacity(0.3),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        color: isDark 
                            ? Colors.white.withOpacity(0.95)
                            : Colors.black87.withOpacity(0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressIndicator() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Progress based on horizontal page scrolling instead of vertical scroll
    final totalPages = 3; // Total number of cards
    final progress = (_currentPage + 1) / totalPages;
    
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          // Percentuale con animazione
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
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
                  style: TextStyle(
                    color: Color(0xFF667eea),
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: 12),
          
          // Progress bar animata personalizzata
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.white.withOpacity(0.1)
                  : Color(0xFF667eea).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: isDark 
                      ? Colors.black.withOpacity(0.1)
                      : Color(0xFF667eea).withOpacity(0.05),
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
                    color: isDark 
                        ? Colors.white.withOpacity(0.1)
                        : Color(0xFF667eea).withOpacity(0.1),
                  ),
                ),
                
                // Progress fill con gradiente
                AnimatedContainer(
                  duration: Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  width: (MediaQuery.of(context).size.width - 48) * _animatedProgressWidth,
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
                if (_animatedProgressWidth > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: (MediaQuery.of(context).size.width - 48) * _animatedProgressWidth,
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
          ),
        ],
      ),
    );
  }
}