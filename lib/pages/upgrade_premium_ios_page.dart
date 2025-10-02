import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter/services.dart';

class UpgradePremiumIOSPage extends StatefulWidget {
  const UpgradePremiumIOSPage({super.key, this.suppressExtraPadding = false});

  final bool suppressExtraPadding;

  @override
  State<UpgradePremiumIOSPage> createState() => _UpgradePremiumIOSPageState();
}

class _UpgradePremiumIOSPageState extends State<UpgradePremiumIOSPage> {
  bool _isAnnualPlan = true;
  final PageController _pageController = PageController(viewportFraction: 0.85);
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  int _selectedPlan = 0; // 0: Gratuito, 1: Premium
  bool _isMenuExpanded = false; // Inizialmente la tendina è abbassata
  bool _isLoading = false;
  String? _currentUserPlanType; // Piano corrente
  bool _hasUsedTrial = false; // Se l'utente ha già utilizzato il trial
  bool _isUserPremium = false; // Se l'utente è premium
  String? _subscriptionStatus; // Status dell'abbonamento
  bool _isUserPremiumFromProfile = false; // Premium dal profilo
  Map<String, dynamic>? _userLocation; // Localizzazione utente
  bool _isLocationPermissionGranted = false; // Permessi localizzazione
  bool _isLocationLoading = false; // Caricamento posizione
  // In-App Purchases (iOS)
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  bool _storeAvailable = false;
  bool _isQueryingProducts = false;
  List<ProductDetails> _products = [];
  static const Set<String> _kProductIds = {
    'com.fluzar.premium.month4.online',
    'com.fluzar.premium.annual1.online',
  };
  
  // Runtime UI log panel for In-App Purchase errors (especially on iOS)
  final List<String> _iapLogs = [];
  final List<String> _allIAPLogs = []; // Lista completa senza limite

  @override
  void initState() {
    super.initState();
    _appendIAPLog('🚀 UpgradePremiumIOSPage initialized');
    _loadCurrentUserPlan();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    _initIAP();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    _purchaseSub?.cancel();
    super.dispose();
  }

  void _appendIAPLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] $message';
    print('IAP: $line');
    
    // Aggiungi sempre alla lista completa (senza limite)
    _allIAPLogs.add(line);
    
    if (mounted) {
      setState(() {
        _iapLogs.add(line);
        // Limita la crescita del log UI per evitare UI pesante
        if (_iapLogs.length > 200) {
          _iapLogs.removeRange(0, _iapLogs.length - 200);
        }
      });
    } else {
      // Fallback if not mounted
      _iapLogs.add(line);
      if (_iapLogs.length > 200) {
        _iapLogs.removeRange(0, _iapLogs.length - 200);
      }
    }
    
    // Copia automaticamente TUTTI i log completi nel clipboard
    final allLogs = _allIAPLogs.join('\n');
    Clipboard.setData(ClipboardData(text: allLogs));
  }

  Future<void> _initIAP() async {
    if (!Platform.isIOS) {
      _appendIAPLog('⚠️ IAP only available on iOS devices');
      return; // Limita agli iPhone/iPad
    }
    
    _appendIAPLog('🚀 Initializing In-App Purchases...');
    
    try {
      final available = await _inAppPurchase.isAvailable();
      _appendIAPLog('Store availability check result: $available');
      setState(() {
        _storeAvailable = available;
      });
      
      if (!available) {
        _appendIAPLog('❌ App Store not available on this device');
        return;
      }
      
      _appendIAPLog('✅ App Store connection established');

      // Ascolta gli aggiornamenti degli acquisti
      _purchaseSub = _inAppPurchase.purchaseStream.listen(
        _onPurchaseUpdated,
        onError: (Object error) {
          _appendIAPLog('Purchase stream error: $error');
        },
        onDone: () {
          _appendIAPLog('Purchase stream completed');
        },
      );

      // Tenta di ripristinare eventuali acquisti (utile in caso di reinstallazioni)
      _appendIAPLog('🔄 Checking for previous purchases...');
      try {
        await _inAppPurchase.restorePurchases();
        _appendIAPLog('✅ Purchase restoration completed');
      } catch (e) {
        _appendIAPLog('⚠️ No previous purchases found: $e');
      }

      await _queryProducts();
    } catch (e) {
      _appendIAPLog('❌ Store initialization failed: $e');
    }
  }

  Future<void> _queryProducts() async {
    if (_isQueryingProducts) return;
    setState(() {
      _isQueryingProducts = true;
    });
    
    _appendIAPLog('🔍 Querying IAP products...');
    
    try {
      // A volte la prima query può tornare vuota: aggiungiamo un retry semplice
      _appendIAPLog('Querying product IDs: ${_kProductIds.join(', ')}');
      ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(_kProductIds);
      
      _appendIAPLog('📦 First query: ${response.productDetails.length} products found');
      
      if (response.productDetails.isEmpty && response.error == null) {
        _appendIAPLog('🔄 Retrying query in 2 seconds...');
        // piccolo backoff prima del retry
        await Future.delayed(const Duration(seconds: 2));
        response = await _inAppPurchase.queryProductDetails(_kProductIds);
        _appendIAPLog('📦 Retry query: ${response.productDetails.length} products found');
      }
      
      if (response.error != null) {
        _appendIAPLog('Products error: ${response.error!.message}');
      }
      
      if (response.productDetails.isEmpty) {
        // Alcuni ID non trovati o non approvati su App Store Connect
        if (response.notFoundIDs.isNotEmpty) {
          _appendIAPLog('❌ Products not found: ${response.notFoundIDs.join(', ')}');
        } else {
          _appendIAPLog('❌ No products available. Verify App Store Connect configuration and product state.');
        }
      } else {
        // Mostra i prodotti trovati
        final productNames = response.productDetails.map((p) => '${p.id}: ${p.price}').join(', ');
        _appendIAPLog('✅ Products loaded successfully: $productNames');
      }
      
      setState(() {
        _products = response.productDetails;
      });
    } catch (e) {
      _appendIAPLog('❌ Failed to fetch products: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isQueryingProducts = false;
        });
      }
    }
  }

  ProductDetails? _productForSelectedPlan() {
    final String id = _selectedPlan == 2
        ? 'com.fluzar.premium.annual1.online'
        : _selectedPlan == 1
            ? 'com.fluzar.premium.month4.online'
            : '';
    if (id.isEmpty) return null;
    try {
      return _products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _startPurchaseForSelectedPlan() async {
    if (!Platform.isIOS) {
      _appendIAPLog('Available on iOS only.');
      return;
    }
    if (!_storeAvailable) {
      _appendIAPLog('App Store not available.');
      return;
    }
    if (_selectedPlan == 0) {
      _appendIAPLog('Please select a Premium plan.');
      return;
    }
    if (_products.isEmpty) {
      _appendIAPLog('🔄 Refreshing products...');
      await _queryProducts();
      if (_products.isEmpty) {
        _appendIAPLog('No products available after refresh.');
        return;
      }
    }
    final product = _productForSelectedPlan();
    if (product == null) {
      _appendIAPLog('Product not available for the selected plan. Selected plan: $_selectedPlan');
      return;
    }

    _appendIAPLog('💳 Starting purchase for ${product.title} (${product.id})...');

    setState(() {
      _isLoading = true;
    });

    try {
      final purchaseParam = PurchaseParam(productDetails: product);
      _appendIAPLog('Created PurchaseParam for product: ${product.id}');
      // Abbonamenti e non-consumabili usano buyNonConsumable su iOS
      final success = await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
      _appendIAPLog('buyNonConsumable result: $success');
      if (!success) {
        _appendIAPLog('❌ Purchase not started.');
        setState(() {
          _isLoading = false;
        });
      } else {
        _appendIAPLog('⏳ Purchase initiated, waiting for user confirmation...');
      }
    } catch (e) {
      _appendIAPLog('❌ Purchase failed: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      _appendIAPLog('📱 Purchase status update: ${purchase.status.name} for ${purchase.productID}');
      
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _appendIAPLog('⏳ Purchase pending approval...');
          setState(() {
            _isLoading = true;
          });
          break;
        case PurchaseStatus.canceled:
          _appendIAPLog('❌ Purchase cancelled by user.');
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          if (purchase.pendingCompletePurchase) {
            _appendIAPLog('Completing cancelled purchase...');
            await _inAppPurchase.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.error:
          _appendIAPLog('❌ Purchase error: ${purchase.error?.message ?? 'unknown error'} | Code: ${purchase.error?.code ?? 'no code'} | Details: ${purchase.error?.details ?? 'no details'}');
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          if (purchase.pendingCompletePurchase) {
            _appendIAPLog('Completing failed purchase...');
            await _inAppPurchase.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _appendIAPLog('✅ Purchase ${purchase.status == PurchaseStatus.purchased ? 'completed' : 'restored'}, activating premium...');
          try {
            // In produzione si dovrebbe validare la ricevuta lato server
            final product = _products.firstWhere(
              (p) => p.id == purchase.productID,
              orElse: () => _productForSelectedPlan() ?? (throw Exception('Prodotto non trovato')),
            );
            final planType = product.id.contains('annual') ? 'annual' : 'monthly';
            _appendIAPLog('Delivering purchase to user: ${purchase.productID} -> $planType');
            await _deliverPurchaseToUser(purchase, planType, product);
            if (mounted) {
              setState(() {
                _isLoading = false;
                _currentUserPlanType = planType;
                _isUserPremium = true;
                _subscriptionStatus = 'active';
              });
              _appendIAPLog('🎉 Premium activated successfully! Welcome to Fluzar Pro.');
            }
          } catch (e) {
            _appendIAPLog('❌ Failed to activate premium: $e');
          } finally {
            if (purchase.pendingCompletePurchase) {
              _appendIAPLog('Completing successful purchase...');
              await _inAppPurchase.completePurchase(purchase);
            }
          }
          break;
      }
    }
  }

  Future<void> _deliverPurchaseToUser(
    PurchaseDetails purchase,
    String planType,
    ProductDetails product,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _appendIAPLog('❌ No current user found when delivering purchase');
      return;
    }
    
    _appendIAPLog('Delivering purchase to user: ${user.uid}');
    final ref = FirebaseDatabase.instance.ref('users/users/${user.uid}');
    final subscriptionRef = ref.child('subscription');

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _appendIAPLog('Updating user isPremium status...');
    await ref.update({
      'isPremium': true,
    });

    _appendIAPLog('Updating subscription data: $planType, ${product.id}, ${purchase.purchaseID}');
    await subscriptionRef.update({
      'isPremium': true,
      'status': 'active',
      'plan_type': planType,
      'platform': 'ios_iap',
      'product_id': product.id,
      'purchase_id': purchase.purchaseID,
      'transaction_date_ms': nowMs,
    });

    _appendIAPLog('✅ Purchase delivered successfully, syncing UI...');
    // Sincronizza UI con i nuovi dati
    await _loadCurrentUserPlan();
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
          // Debug
          // print('Utente ha già utilizzato il trial: $_hasUsedTrial');
          // print('Utente è premium dal profilo: $_isUserPremiumFromProfile');
        }
      }

      // Carica la localizzazione dell'utente
      if (user != null) {
        try {
          final locationSnapshot = await FirebaseDatabase.instance
              .ref()
              .child('users/users/${user.uid}/profile/location')
              .get();

          if (locationSnapshot.exists) {
            setState(() {
              _userLocation = Map<String, dynamic>.from(locationSnapshot.value as Map);
              _isLocationPermissionGranted = true;
            });
          } else {
            setState(() {
              _isLocationPermissionGranted = false;
            });
          }
        } catch (e) {
          setState(() {
            _isLocationPermissionGranted = false;
          });
        }
      }

      // Verifica stato abbonamento e piano corrente da Realtime Database
      if (user != null) {
        final database = FirebaseDatabase.instance.ref();
        final subscriptionRef = database.child('users/users/${user.uid}/subscription');
        final subscriptionSnapshot = await subscriptionRef.get();

        if (subscriptionSnapshot.exists) {
          final subscriptionData = subscriptionSnapshot.value as Map<dynamic, dynamic>;
          setState(() {
            _isUserPremium = subscriptionData['isPremium'] == true;
            _subscriptionStatus = subscriptionData['status'] as String?;
            _currentUserPlanType = (subscriptionData['plan_type'] as String?)?.toLowerCase();
          });
        }
      }

      // Imposta il piano di default in base al piano corrente
      if (_currentUserPlanType == 'monthly') {
        _selectedPlan = 1;
        _currentPage = 1;
      } else if (_currentUserPlanType == 'annual') {
        _selectedPlan = 2;
        _currentPage = 2;
      }

      _isMenuExpanded = false;

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      // print('Errore nel caricamento del piano corrente: $e');
    }
  }

  /// Gestisce i permessi di localizzazione e ottiene la posizione dell'utente
  Future<bool> _handleLocationPermission() async {
    setState(() {
      _isLocationLoading = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showErrorSnackBar('Location services are disabled. Please enable them to continue.');
        setState(() {
          _isLocationLoading = false;
        });
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showErrorSnackBar('Location permission denied.');
          setState(() {
            _isLocationLoading = false;
          });
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showErrorSnackBar('Location permission permanently denied. Please enable it in settings.');
        setState(() {
          _isLocationLoading = false;
        });
        return false;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        _userLocation = {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'country': place.country ?? '',
          'state': place.administrativeArea ?? '',
          'city': place.locality ?? '',
          'postalCode': place.postalCode ?? '',
          'street': place.street ?? '',
          'address': '${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}, ${place.postalCode ?? ''}, ${place.country ?? ''}'.trim(),
        };

        setState(() {
          _isLocationPermissionGranted = true;
          _isLocationLoading = false;
        });

        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await FirebaseDatabase.instance
                .ref()
                .child('users/users/${user.uid}/profile/location')
                .set(_userLocation);
          }
        } catch (e) {
          // ignore
        }

        return true;
      } else {
        _showErrorSnackBar('Unable to get address from location.');
        setState(() {
          _isLocationLoading = false;
        });
        return false;
      }
    } catch (e) {
      _showErrorSnackBar('Error getting location: $e');
      setState(() {
        _isLocationLoading = false;
      });
      return false;
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  bool _isButtonDisabled() {
    if (_isLoading || _isLocationLoading) return true;
    return false;
  }

  bool _isCurrentPlan(int selectedPlan) {
    if (_currentUserPlanType == null) return false;
    if (selectedPlan == 1 && _currentUserPlanType == 'monthly') return true;
    if (selectedPlan == 2 && _currentUserPlanType == 'annual') return true;
    return false;
  }

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

  Future<void> _onUpgradePressed() async {
    _appendIAPLog('🎯 User pressed upgrade button - Selected plan: $_selectedPlan');
    if (_selectedPlan == 1 || _selectedPlan == 2) {
      await _startPurchaseForSelectedPlan();
    } else {
      _appendIAPLog('❌ No premium plan selected');
      _showErrorSnackBar('Please select a Premium plan.');
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showInfoSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.blue[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showIAPLogsDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bug_report_outlined,
                    size: 20,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'In-App Purchase Debug Logs',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'All logs are automatically copied to clipboard',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (_allIAPLogs.isNotEmpty) {
                          final allLogs = _allIAPLogs.join('\n');
                          Clipboard.setData(ClipboardData(text: allLogs));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.copy, color: Colors.white, size: 16),
                                  const SizedBox(width: 8),
                                  const Text('All IAP logs copied to clipboard'),
                                ],
                              ),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy All'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _iapLogs.clear();
                          _allIAPLogs.clear();
                        });
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Clear All'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white24 : Colors.black12,
                    ),
                  ),
                  child: _iapLogs.isEmpty
                      ? Center(
                          child: Text(
                            'No IAP logs yet.\nTry making a purchase to see debug information.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45,
                              fontSize: 14,
                            ),
                          ),
                        )
                      : Scrollbar(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _iapLogs.length,
                            itemBuilder: (context, index) {
                              final log = _iapLogs[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: SelectableText(
                                  log,
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.3,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              );
                            },
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
                  top: MediaQuery.of(context).size.height * 0.05 + 25,
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
                  bottom: 120 + MediaQuery.of(context).size.height * 0.13,
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

    return SizedBox(
      height: 200,
      child: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(20),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'Unlock full potential',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
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
                    ),
                    if (Platform.isIOS) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _showIAPLogsDialog(),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.bug_report_outlined,
                            size: 16,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'More power, more automation, more visibility with Fluzar pro',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
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
            'text': 'AI Analysis: Not available',
            'icon': Icons.psychology_outlined,
            'isAvailable': false,
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
          if (!_hasUsedTrial)
            {
              'text': '3 days free trial included',
              'icon': Icons.free_breakfast,
              'isAvailable': true,
            },
          {
            'text': 'Save 28%',
            'icon': Icons.savings,
            'isAvailable': true,
          },
        ],
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 350,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
                _selectedPlan = index;
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
                          return const LinearGradient(
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
                                        return const LinearGradient(
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
            if ((!_isUserPremiumFromProfile || _selectedPlan != 0) && !_isMenuExpanded)
              GestureDetector(
                onTap: () {
                  setState(() {
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
                          await _onUpgradePressed();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading || _isLocationLoading
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
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Messaggi informativi sui trial e prezzi
                  if (_selectedPlan == 1 && !_hasUsedTrial)
                    Text(
                      'Free 3-day trial, then €6.99/month with automatic renewal.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    )
                  else if (_selectedPlan == 2 && !_hasUsedTrial)
                    Text(
                      'Free 3-day trial, then €59.99/annual with automatic renewal.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
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


