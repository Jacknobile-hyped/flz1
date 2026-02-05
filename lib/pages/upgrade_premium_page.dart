import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'premium_plan_page.dart';
import '../services/stripe_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'payment_success_page.dart'; // Added import for PaymentSuccessPage
import 'dart:ui';

class UpgradePremiumPage extends StatefulWidget {
  const UpgradePremiumPage({super.key, this.suppressExtraPadding = false, this.fromGettingStarted = false});

  final bool suppressExtraPadding;
  final bool fromGettingStarted;

  @override
  State<UpgradePremiumPage> createState() => _UpgradePremiumPageState();
}

class _UpgradePremiumPageState extends State<UpgradePremiumPage> {
  bool _isAnnualPlan = true;
  final PageController _pageController = PageController(viewportFraction: 0.85);
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  int _selectedPlan = 0; // 0: Gratuito, 1: Premium
  bool _isMenuExpanded = false; // Inizialmente la tendina è abbassata
  bool _isLoading = false;
  String? _currentUserPlanType; // Aggiungo variabile per il piano corrente
  bool _hasUsedTrial = false; // Variabile per tracciare se l'utente ha già utilizzato il trial
  bool _isUserPremium = false; // Variabile per tracciare se l'utente è premium
  String? _subscriptionStatus; // Variabile per tracciare lo status dell'abbonamento
  bool _isUserPremiumFromProfile = false; // Variabile per tracciare se l'utente è premium dal profilo

  @override
  void initState() {
    super.initState();
    _loadCurrentUserPlan(); // Carica il piano corrente dell'utente
    
    // Scrolla la pagina verso il basso dopo che il widget è stato costruito
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Scrolla la pagina verso il basso per mostrare i piani
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Carica il piano corrente dell'utente dal database
  Future<void> _loadCurrentUserPlan() async {
    try {
      // Carica le informazioni dell'utente dal database
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final database = FirebaseDatabase.instance.ref();
        final userRef = database.child('users/users/${user.uid}');
        final snapshot = await userRef.get();
        
        if (snapshot.exists) {
          final userData = snapshot.value as Map<dynamic, dynamic>;
          setState(() {
            _hasUsedTrial = userData['has_used_trial'] == true;
            _isUserPremiumFromProfile = userData['isPremium'] == true;
          });
          print('Utente ha già utilizzato il trial: $_hasUsedTrial');
          print('Utente è premium dal profilo: $_isUserPremiumFromProfile');
        }
      }
      
      // Verifica se l'utente è premium dal path subscription/isPremium e lo status
      if (user != null) {
        final database = FirebaseDatabase.instance.ref();
        final subscriptionRef = database.child('users/users/${user.uid}/subscription');
        final subscriptionSnapshot = await subscriptionRef.get();
        
        if (subscriptionSnapshot.exists) {
          final subscriptionData = subscriptionSnapshot.value as Map<dynamic, dynamic>;
          setState(() {
            _isUserPremium = subscriptionData['isPremium'] == true;
            _subscriptionStatus = subscriptionData['status'] as String?;
          });
          print('Utente è premium: $_isUserPremium');
          print('Status abbonamento: $_subscriptionStatus');
        }
      }
      
      final subscription = await StripeService.getUserSubscriptionFromDatabase();
      if (subscription != null) {
        setState(() {
          _currentUserPlanType = subscription['plan_type'] as String?;
        });
        print('Piano corrente dell\'utente: $_currentUserPlanType');
        
        // Verifica se l'abbonamento è in trial e se il trial è finito
        await _checkAndCompleteTrialSubscription(subscription);
        
        // Imposta il piano di default in base al piano corrente
        if (_currentUserPlanType == 'monthly') {
          _selectedPlan = 1; // Premium mensile
          _currentPage = 1;
        } else if (_currentUserPlanType == 'annual') {
          _selectedPlan = 2; // Premium annuale
          _currentPage = 2;
        }
        
        // Assicurati che la tendina rimanga abbassata
        _isMenuExpanded = false;
        
        // Aggiorna il PageController se necessario
        if (_pageController.hasClients) {
          _pageController.animateToPage(
            _currentPage,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
        
        // Scrolla verso il basso dopo aver caricato il piano
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    } catch (e) {
      print('Errore nel caricamento del piano corrente: $e');
    }
  }

  /// Verifica lo stato dell'abbonamento (con setup_future_usage, Stripe gestisce automaticamente)
  Future<void> _checkAndCompleteTrialSubscription(Map<String, dynamic> subscription) async {
    try {
      final status = subscription['status'] as String?;
      final trialEnd = subscription['trial_end'] as int?;
      final subscriptionId = subscription['subscription_id'] as String?;
      
      if (status == 'trialing' && trialEnd != null && subscriptionId != null) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000; // Timestamp in secondi
        
        // Se il trial è finito, Stripe dovrebbe aver già gestito automaticamente il pagamento
        if (now >= trialEnd) {
          print('Trial finito. Con setup_future_usage, Stripe dovrebbe aver gestito automaticamente il pagamento.');
          // Ricarica il piano per aggiornare lo stato
          await _loadCurrentUserPlan();
        }
      } else if (status == 'paused' && subscriptionId != null) {
        // Se l'abbonamento è in pausa, potrebbe essere necessario un intervento manuale
        print('Abbonamento in pausa. Potrebbe essere necessario aggiungere un metodo di pagamento.');
        // Ricarica il piano per aggiornare lo stato
        await _loadCurrentUserPlan();
      }
    } catch (e) {
      print('Errore nella verifica del trial: $e');
    }
  }


  /// Determina se il piano selezionato è quello corrente dell'utente
  bool _isCurrentPlan(int selectedPlan) {
    if (_currentUserPlanType == null) return false;
    
    if (selectedPlan == 1 && _currentUserPlanType == 'monthly') {
      return true;
    } else if (selectedPlan == 2 && _currentUserPlanType == 'annual') {
      return true;
    }
    return false;
  }


  /// Mostra un messaggio di errore tramite SnackBar
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(16),
        ),
      );
    }
  }

  /// Determina se il pulsante deve essere disabilitato
  bool _isButtonDisabled() {
    // Disabilita solo durante operazioni in corso
    if (_isLoading) return true;

    return false;
  }

  /// Ottiene il testo del pulsante in base al piano selezionato
  String _getButtonText(int selectedPlan) {
    if (selectedPlan == 0) {
      return 'Current plan';
    } else if (_isCurrentPlan(selectedPlan)) {
      if (_subscriptionStatus == 'cancelled') {
        return 'Select this plan';
      }
      return 'View subscription details';
    } else {
      if (_hasUsedTrial) {
        return 'Select this plan';
      } else {
        return 'Start 3-Day Free Trial';
      }
    }
  }

  /// Gestisce il reindirizzamento alla pagina di billing di Stripe
  Future<void> _handleBillingRedirect() async {
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

  /// Gestisce l'upgrade al piano Premium tramite Stripe Payment Sheet
  Future<void> _handlePremiumUpgrade() async {
    // Se il piano selezionato è quello corrente, non fare nulla
    if (_isCurrentPlan(_selectedPlan)) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('Iniziando processo di upgrade premium per piano: ${_selectedPlan == 1 ? "mensile" : "annuale"}');
      
      // Reset flag per mostrare la pagina di successo dopo ogni nuovo pagamento
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasSeenPaymentSuccess', false);
      
      // Ottieni l'email dell'utente corrente
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception('Utente non autenticato o email non disponibile');
      }

      print('Utente autenticato: ${user.email}');

      // Inizializza Stripe se non è già stato fatto
      try {
        print('Inizializzando Stripe...');
        await StripeService.initializeStripe();
        print('Stripe inizializzato con successo');
      } catch (e) {
        print('Errore nell\'inizializzazione di Stripe: $e');
        // Continua comunque, potrebbe essere già inizializzato
      }

      // La localizzazione sarà determinata automaticamente lato server dall'IP
      print('✅ La localizzazione per la tassazione sarà determinata automaticamente dall\'IP lato server');
      
      // Presenta il Payment Sheet (senza userLocation - sarà determinato lato server)
      print('Presentando Payment Sheet...');
      final paymentResult = await StripeService.presentPaymentSheet(
        context: context,
        customerEmail: user.email!,
        planType: _selectedPlan == 1 ? 'monthly' : 'annual',
        hasUsedTrial: _hasUsedTrial,
      );

      if (paymentResult != null && paymentResult['success'] == true) {
        print('Pagamento completato con successo');
        print('Dati abbonamento ricevuti: ${paymentResult['subscription']}');
        print('Customer ID: ${paymentResult['subscription']?['customer_id']}');
        print('Tipo di dati subscription: ${paymentResult['subscription'].runtimeType}');
        print('Chiavi disponibili in subscription: ${paymentResult['subscription'].keys.toList()}');
        
        // Aggiorna il piano corrente
        await _loadCurrentUserPlan();
        // Naviga alla pagina di successo con i dettagli del pagamento
        if (mounted) {
          final subscriptionData = Map<String, dynamic>.from(paymentResult['subscription']);
          print('UpgradePremiumPage: Dati passati alla PaymentSuccessPage: ${subscriptionData.toString()}');
          print('UpgradePremiumPage: Customer ID passato: ${subscriptionData['customer_id']}');
          print('UpgradePremiumPage: Tipo di dati: ${subscriptionData.runtimeType}');
          
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => PaymentSuccessPage(
                subscriptionId: paymentResult['payment_intent_id'],
                planType: _selectedPlan == 1 ? 'monthly' : 'annual', // Aggiungo il planType
                subscriptionData: subscriptionData, // Passa i dati completi dell'abbonamento
              ),
            ),
          );
        }
      } else {
        print('Pagamento non completato');
        // Non mostrare alcuno SnackBar se il pagamento è stato annullato
      }
    } catch (e) {
      print('Errore durante l\'upgrade premium: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final plans = [
      {
        'title': 'Basic',
        'price': 'Free',
        'period': '',
        'gradient': [const Color(0xFF667eea), const Color(0xFF764ba2)],
      },
      {
        'title': 'Premium',
        'price': '€6,99',
        'period': '/month',
        'gradient': [const Color(0xFFFF6B6B), const Color(0xFFEE0979)],
      },
      {
        'title': 'Premium Annual',
        'price': '€59,99',
        'period': '/year',
        'gradient': [const Color(0xFF00C9FF), const Color(0xFF92FE9D)],
      },
    ];

    final selectedGradient = plans[_selectedPlan]['gradient'] as List<Color>;
    
    return Scaffold(
      body: Stack(
        children: [
          // Animated background
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: selectedGradient,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
          ),
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(
                  top: widget.fromGettingStarted 
                      ? MediaQuery.of(context).size.height * 0.05 + 30 - 50 // Ridotto di 70 pixel se arriva da Getting Started
                      : MediaQuery.of(context).size.height * 0.05 + 30, // 11% dell'altezza dello schermo + 20px
                  bottom: widget.fromGettingStarted ? 40 : 0, // Aggiunto padding sotto se arriva da Getting Started
                ),
                sliver: SliverToBoxAdapter(
                  child: _buildHeroHeader(context),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildPlansCarousel(context),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom: 130 + MediaQuery.of(context).size.height * 0.0, // 130px + 7% dell'altezza dello schermo (diminuito di 50px)
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildStickyCTA(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        minHeight: 120,
        maxHeight: widget.fromGettingStarted ? 160 : 140, // Altezza maggiore se arriva da Getting Started
      ),
      child: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(16), // Ridotto padding da 20 a 16
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Unlock full potential',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18, // Ridotto da 20 a 18
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.3),
                        offset: const Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'More power, more automation, more visibility with Fluzar pro',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                    fontSize: 13, // Ridotto da 14 a 13
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlansCarousel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final plans = [
      {
        'name': 'Basic',
        'price': 'Free',
        'features': [
          {
            'text': 'Compare up to 3 videos',
            'icon': Icons.compare_arrows,
            'isAvailable': true,
          },
          {
            'text': 'Videos per day: Limited',
            'icon': Icons.video_library_outlined,
            'isAvailable': true,
          },
          {
            'text': 'Credits: Limited',
            'icon': Icons.stars_outlined,
            'isAvailable': true,
          },
          {
            'text': 'AI Analysis: Limited',
            'icon': Icons.psychology_outlined,
            'isAvailable': true,
          },
          {
            'text': 'Priority support: Not available',
            'icon': Icons.support_agent_outlined,
            'isAvailable': false,
          },
        ],
      },
      {
        'name': 'Premium',
        'price': '€6,99/month',
        'trial': _hasUsedTrial ? null : '3 days free trial',
        'features': [
          {
            'text': 'Compare up to 10 videos',
            'icon': Icons.compare_arrows,
            'isAvailable': true,
          },
          {
            'text': 'Videos per day: Unlimited',
            'icon': Icons.video_library,
            'isAvailable': true,
          },
          {
            'text': 'Credits: Unlimited',
            'icon': Icons.stars,
            'isAvailable': true,
          },
          {
            'text': 'AI Analysis: Unlimited',
            'icon': Icons.psychology,
            'isAvailable': true,
          },
          {
            'text': 'Priority support: Premium',
            'icon': Icons.support_agent,
            'isAvailable': true,
          },
          // Mostra "3 days free trial included" solo se l'utente non ha già utilizzato il trial
          if (!_hasUsedTrial)
            {
              'text': '3 days free trial included',
              'icon': Icons.free_breakfast,
              'isAvailable': true,
            },
        ],
      },
      {
        'name': 'Premium Annual',
        'price': '€59,99/year',
        'trial': _hasUsedTrial ? null : '3 days free trial',
        'features': [
          {
            'text': '3 months free',
            'icon': Icons.savings,
            'isAvailable': true,
          },
          {
            'text': 'Compare up to 10 videos',
            'icon': Icons.compare_arrows,
            'isAvailable': true,
          },
          {
            'text': 'Videos per day: Unlimited',
            'icon': Icons.video_library,
            'isAvailable': true,
          },
          {
            'text': 'Credits: Unlimited',
            'icon': Icons.stars,
            'isAvailable': true,
          },
          {
            'text': 'AI Analysis: Unlimited',
            'icon': Icons.psychology,
            'isAvailable': true,
          },
          {
            'text': 'Priority support: Premium',
            'icon': Icons.support_agent,
            'isAvailable': true,
          },
          // Mostra "3 days free trial included" solo se l'utente non ha già utilizzato il trial
          if (!_hasUsedTrial)
            {
              'text': '3 days free trial included',
              'icon': Icons.free_breakfast,
              'isAvailable': true,
            },
        ],
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        SizedBox(
          height: 370,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
                _selectedPlan = index;
                // Mantieni la tendina chiusa se l'utente è premium dal profilo e seleziona il piano Basic
                if (_isUserPremiumFromProfile && index == 0) {
                  _isMenuExpanded = false;
                } else {
                  _isMenuExpanded = true;
                }
              });
              
            },
            padEnds: true,
            itemCount: plans.length,
            itemBuilder: (context, index) {
              final plan = plans[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                    // Ombra interna per effetto glass opaco sui bordi
                    BoxShadow(
                      color: Colors.white.withOpacity(0.8),
                      blurRadius: 2,
                      spreadRadius: -1,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan['name'] as String,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ShaderMask(
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
                          plan['price'] as String,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (plan['trial'] != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            plan['trial'] as String,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      ...(plan['features'] as List<Map<String, dynamic>>).map((feature) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: feature['isAvailable'] as bool
                                  ? ShaderMask(
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
                                        feature['icon'] as IconData,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    )
                                  : Icon(
                                      feature['icon'] as IconData,
                                      color: Colors.grey[400],
                                      size: 18,
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Row(
                                children: [
                            Expanded(
                              child: Text(
                                feature['text'] as String,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: feature['isAvailable'] as bool 
                                      ? Colors.grey[700] 
                                      : Colors.grey[400],
                                      ),
                                    ),
                                  ),
                                  if (feature['hasLink'] == true)
                                    GestureDetector(
                                      onTap: () async {
                                        final url = Uri.parse(feature['linkUrl'] as String);
                                        if (await canLaunchUrl(url)) {
                                          await launchUrl(url, mode: LaunchMode.externalApplication);
                                        }
                                      },
                                      child: Text(
                                        feature['linkText'] as String,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            plans.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _currentPage == index ? 24 : 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _currentPage == index
                    ? Colors.white
                    : Colors.white.withOpacity(0.4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStickyCTA(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final plans = [
      {
        'title': 'Basic',
        'price': 'Free',
        'period': '',
        'gradient': [const Color(0xFF667eea), const Color(0xFF764ba2)],
      },
      {
        'title': 'Premium',
        'price': '€6,99',
        'period': '/month',
        'gradient': [const Color(0xFFFF6B6B), const Color(0xFFEE0979)],
      },
      {
        'title': 'Premium Annual',
        'price': '€59,99',
        'period': '/year',
        'savings': 'Save 28%',
        'gradient': [const Color(0xFF00C9FF), const Color(0xFF92FE9D)],
      },
    ];

    final selectedPlan = plans[_selectedPlan];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mostra la freccia solo se l'utente non è premium dal profilo o se il piano selezionato non è Basic
            if ((!_isUserPremiumFromProfile || _selectedPlan != 0) && !_isMenuExpanded)
              GestureDetector(
                onTap: () {
                  setState(() {
                    // Non permettere di aprire la tendina se l'utente è premium dal profilo e il piano è Basic
                    if (!(_isUserPremiumFromProfile && _selectedPlan == 0)) {
                      _isMenuExpanded = true;
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Icon(
                    Icons.keyboard_arrow_up,
                    color: isDark ? Colors.white : Colors.black87,
                    size: 20,
                  ),
                ),
              ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              firstChild: Column(
                children: [
                  // Spazio del 5% sotto alla freccia quando la tendina è chiusa
                  SizedBox(height: MediaQuery.of(context).size.height * 0.10),
                ],
              ),
              secondChild: Column(
                children: [
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: selectedPlan['gradient'] as List<Color>,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton(
                        onPressed: _isButtonDisabled() ? null : () async {
                          // Se il piano selezionato è quello corrente e lo status non è "cancelled", reindirizza alla pagina di billing
                          if (_isCurrentPlan(_selectedPlan) && _subscriptionStatus != 'cancelled') {
                            await _handleBillingRedirect();
                          }
                          // Se il piano selezionato è quello corrente ma lo status è "cancelled", gestisci l'upgrade premium
                          else if (_isCurrentPlan(_selectedPlan) && _subscriptionStatus == 'cancelled') {
                            await _handlePremiumUpgrade();
                          }
                          // Altrimenti, gestisci l'upgrade premium
                          else if (_selectedPlan == 1 || _selectedPlan == 2) {
                            await _handlePremiumUpgrade();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                _getButtonText(_selectedPlan),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                  // Tassazione automatica inclusa - nessun dettaglio visibile per l'utente
                  // Spazio del 5% sotto i pulsanti
                  SizedBox(height: widget.suppressExtraPadding ? 0 : MediaQuery.of(context).size.height * 0.10),
                ],
              ),
              crossFadeState: (_isMenuExpanded && (!_isUserPremiumFromProfile || _selectedPlan != 0)) ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            ),
          ],
        ),
      ),
    );
  }
} 