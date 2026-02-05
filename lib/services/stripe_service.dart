import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StripeService {
  // IMPORTANTE: Le chiavi Stripe sono gestite dal worker Cloudflare
  // Non inserire chiavi segrete qui!
  static const String _backendUrl = 'https://stripe-worker.giuseppemaria162.workers.dev'; // URL del worker Cloudflare

  // ID del prezzo da Stripe Dashboard
  static const String _priceId = 'price_1RimAwPXu7NNq0NK1QiV5cjI';

  /// Inizializza Stripe con la chiave pubblica
  static Future<void> initializeStripe() async {
    try {
      // Ottieni la chiave pubblica dal worker
      final response = await http.get(
        Uri.parse('$_backendUrl/get-publishable-key'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final publishableKey = data['publishableKey'];
        
        if (publishableKey != null) {
          Stripe.publishableKey = publishableKey;
          await Stripe.instance.applySettings();
          print('Stripe inizializzato con successo');
        } else {
          throw Exception('Chiave pubblica non disponibile');
        }
      } else {
        throw Exception('Errore nell\'inizializzazione di Stripe: ${response.statusCode}');
      }
    } catch (e) {
      print('Errore durante l\'inizializzazione di Stripe: $e');
      rethrow;
    }
  }

  /// Crea un Payment Intent per il primo mese
  /// NOTA: userLocation è opzionale - la localizzazione sarà determinata dall'IP lato server
  static Future<String?> createPaymentIntent({
    required String customerEmail,
    int amount = 699, // €6.99 in centesimi
    String planType = 'monthly',
  }) async {
    try {
      print('Creazione payment intent per: $customerEmail, amount: $amount');
      
      // Determina l'importo in base al tipo di piano
      int finalAmount = amount;
      if (planType == 'annual') {
        finalAmount = 5999; // €59.99 in centesimi per il piano annuale
        print('Piano annuale selezionato - Importo: €59.99');
      } else {
        print('Piano mensile selezionato - Importo: €6.99');
      }
      
      // Nota: La tassazione automatica è ora gestita tramite Tax Calculation API
      // collegata al Payment Intent tramite hooks[inputs][tax][calculation]

      final response = await http.post(
        Uri.parse('$_backendUrl/create-payment-intent'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'customer_email': customerEmail,
          'amount': finalAmount,
          'plan_type': planType,
          // La localizzazione sarà determinata automaticamente dall'IP lato server
        }),
      );

      print('Risposta del worker: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['clientSecret']; // Client secret per Payment Sheet
      } else {
        print('Errore nella creazione del payment intent: ${response.statusCode}');
        print('Risposta: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Errore durante la creazione del payment intent: $e');
      return null;
    }
  }

  /// Crea un abbonamento mensile con free trial di 3 giorni
  /// NOTA: userLocation è opzionale - la localizzazione sarà determinata dall'IP lato server
  static Future<Map<String, dynamic>?> createSubscription({
    required String customerEmail,
    String paymentMethodId = '',
    bool hasUsedTrial = false,
  }) async {
    try {
      // Nota: La tassazione automatica è gestita dal worker Cloudflare
      // con il parametro automatic_tax[enabled]=true
      final response = await http.post(
        Uri.parse('$_backendUrl/create-subscription'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'customer_email': customerEmail,
          'payment_method_id': paymentMethodId,
          'has_used_trial': hasUsedTrial,
          // La localizzazione sarà determinata automaticamente dall'IP lato server
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final subscription = data['subscription'];
        
        // Aggiungi informazioni sul trial solo se l'utente non l'ha già utilizzato
        if (subscription != null) {
          // Non sovrascrivere i dati originali, aggiungi solo se non esistono
          if (subscription['has_trial'] == null) {
            subscription['has_trial'] = !hasUsedTrial;
          }
          if (subscription['trial_days'] == null) {
            subscription['trial_days'] = hasUsedTrial ? 0 : 3;
          }
          if (subscription['trial_end'] == null) {
            subscription['trial_end'] = subscription['current_period_end'];
          }
          if (subscription['plan_type'] == null) {
            subscription['plan_type'] = 'monthly';
          }
        }
        
        print('StripeService: Dati ricevuti dal worker: ${data.toString()}');
        print('StripeService: Subscription ricevuta: ${subscription.toString()}');
        print('StripeService: Customer ID ricevuto: ${subscription?['customer_id']}');
        print('StripeService: Tipo di subscription: ${subscription.runtimeType}');
        print('StripeService: Chiavi in subscription: ${subscription?.keys.toList()}');
        
        return subscription;
      } else {
        print('Errore nella creazione dell\'abbonamento: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Errore durante la creazione dell\'abbonamento: $e');
      return null;
    }
  }

  /// Crea un abbonamento annuale con free trial di 3 giorni
  /// NOTA: userLocation è opzionale - la localizzazione sarà determinata dall'IP lato server
  static Future<Map<String, dynamic>?> createAnnualSubscription({
    required String customerEmail,
    String paymentMethodId = '',
    bool hasUsedTrial = false,
  }) async {
    try {
      // Nota: La tassazione automatica è gestita dal worker Cloudflare
      // con il parametro automatic_tax[enabled]=true
      final response = await http.post(
        Uri.parse('$_backendUrl/create-annual-subscription'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'customer_email': customerEmail,
          'payment_method_id': paymentMethodId,
          'has_used_trial': hasUsedTrial,
          // La localizzazione sarà determinata automaticamente dall'IP lato server
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final subscription = data['subscription'];
        
        // Aggiungi informazioni sul trial solo se l'utente non l'ha già utilizzato
        if (subscription != null) {
          // Aggiungi informazioni sul trial solo se l'utente non l'ha già utilizzato
          if (subscription['has_trial'] == null) {
            subscription['has_trial'] = !hasUsedTrial;
          }
          if (subscription['trial_days'] == null) {
            subscription['trial_days'] = hasUsedTrial ? 0 : 3;
          }
          if (subscription['trial_end'] == null) {
            subscription['trial_end'] = subscription['current_period_end'];
          }
          if (subscription['plan_type'] == null) {
            subscription['plan_type'] = 'annual';
          }
        }
        
        print('StripeService: Dati abbonamento annuale ricevuti dal worker: ${data.toString()}');
        print('StripeService: Subscription annuale ricevuta: ${subscription.toString()}');
        print('StripeService: Customer ID ricevuto: ${subscription?['customer_id']}');
        
        return subscription;
      } else {
        print('Errore nella creazione dell\'abbonamento annuale: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Errore durante la creazione dell\'abbonamento annuale: $e');
      return null;
    }
  }

  /// Crea una sessione del customer portal per gestire l'abbonamento
  static Future<String?> createCustomerPortalSession({
    required String customerEmail,
    required String returnUrl,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/create-portal-session'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'customer_email': customerEmail,
          'return_url': returnUrl,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url']; // URL del customer portal
      } else {
        print('Errore nella creazione del customer portal: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Errore durante la creazione del customer portal: $e');
      return null;
    }
  }

  /// Presenta il Payment Sheet per il pagamento
  /// NOTA: La localizzazione per la tassazione sarà determinata automaticamente dall'IP lato server
  static Future<Map<String, dynamic>?> presentPaymentSheet({
    required BuildContext context,
    required String customerEmail,
    String planType = 'monthly',
    bool hasUsedTrial = false,
  }) async {
    try {
      print('Iniziando processo di pagamento per: $customerEmail');
      
      // Crea l'abbonamento appropriato in base al tipo di piano
      // La localizzazione per la tassazione sarà determinata automaticamente dall'IP lato server
      Map<String, dynamic>? subscription;
      if (planType == 'annual') {
        print('Creando abbonamento annuale...');
        subscription = await createAnnualSubscription(
          customerEmail: customerEmail,
          paymentMethodId: '', // Non abbiamo ancora il payment method ID
          hasUsedTrial: hasUsedTrial,
        );
      } else {
        print('Creando abbonamento mensile...');
        subscription = await createSubscription(
          customerEmail: customerEmail,
          paymentMethodId: '', // Non abbiamo ancora il payment method ID
          hasUsedTrial: hasUsedTrial,
        );
      }

      if (subscription == null) {
        throw Exception('Impossibile creare l\'abbonamento');
      }

      print('Abbonamento creato con successo, ID: ${subscription['id']}');
      print('La tassazione automatica sarà gestita da Stripe in base alla localizzazione determinata dall\'IP');

      // Ottieni il client secret dal payment intent dell'abbonamento
      String? clientSecret;
      print('Dettagli abbonamento: ${subscription.toString()}');
      
      if (subscription['latest_invoice'] != null) {
        final latestInvoice = subscription['latest_invoice'];
        print('Latest invoice: ${latestInvoice.toString()}');
        
        if (latestInvoice['payment_intent'] != null) {
          final paymentIntent = latestInvoice['payment_intent'];
          print('Payment intent: ${paymentIntent.toString()}');
          clientSecret = paymentIntent['client_secret'];
          print('Client secret ottenuto dall\'abbonamento: $clientSecret');
        } else {
          print('Payment intent non trovato nell\'invoice');
        }
      } else {
        print('Latest invoice non trovato nell\'abbonamento');
      }

      if (clientSecret == null) {
        // Prova a creare un payment intent separato come fallback
        print('Tentativo di creare un payment intent separato...');
        clientSecret = await createPaymentIntent(
          customerEmail: customerEmail,
          planType: planType,
          // La localizzazione sarà determinata automaticamente dall'IP lato server
        );
        
        if (clientSecret == null) {
          throw Exception('Impossibile ottenere il client secret dall\'abbonamento o creare un payment intent separato');
        }
      }

      // Configura il Payment Sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Fluzar Premium',
          style: ThemeMode.system,
          appearance: PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: const Color(0xFF6C63FF),
            ),
            shapes: PaymentSheetShape(
              borderRadius: 12,
              shadow: PaymentSheetShadowParams(color: Colors.black),
            ),
          ),
        ),
      );

      print('Payment Sheet configurato, presentando...');

      // Presenta il Payment Sheet
      await Stripe.instance.presentPaymentSheet();

      // Se arriviamo qui, il pagamento è stato completato con successo
      print('Pagamento completato con successo');
      print('Dati abbonamento completi dal worker: ${subscription.toString()}');
      print('Customer ID nell\'abbonamento: ${subscription['customer_id']}');
      
      // Estrai il payment intent ID dal client secret
      final paymentIntentId = clientSecret.split('_secret_')[0];
      
      // Estrai il payment method ID dal payment intent
      String? paymentMethodId;
      try {
        final paymentIntent = await Stripe.instance.retrievePaymentIntent(clientSecret);
        if (paymentIntent.paymentMethodId != null && paymentIntent.paymentMethodId!.isNotEmpty) {
          paymentMethodId = paymentIntent.paymentMethodId;
          print('Payment method ID salvato: $paymentMethodId');
          
          // Aggiorna l'abbonamento con il payment method ID
          if (subscription != null && subscription['id'] != null) {
            print('Aggiornando abbonamento con il payment method ID...');
            
            // Salva il customer_id originale
            final originalCustomerId = subscription['customer_id'];
            
            final updatedSubscription = await completeSubscription(
              subscriptionId: subscription['id'],
              paymentMethodId: paymentMethodId,
            );
            
            if (updatedSubscription != null) {
              // Preserva il customer_id originale se non è presente nell'aggiornamento
              if (originalCustomerId != null && updatedSubscription['customer_id'] == null) {
                updatedSubscription['customer_id'] = originalCustomerId;
                print('Customer ID originale preservato: $originalCustomerId');
              }
              
              subscription = updatedSubscription;
              print('Abbonamento aggiornato con successo');
            }
          }
        } else {
          print('Payment method ID non disponibile nel payment intent');
        }
      } catch (e) {
        print('Errore nel recupero del payment method ID: $e');
      }

      // Con payment_behavior: 'default_incomplete', Stripe gestirà automaticamente
      // il pagamento futuro quando il trial finisce
      if (subscription != null) {
        print('Abbonamento creato con payment_behavior: default_incomplete. Stripe gestirà automaticamente il pagamento futuro.');
      }

      // La transazione fiscale sarà gestita automaticamente da Stripe quando il pagamento viene completato

      // Aggiorna il database Firebase solo se l'abbonamento è stato creato con successo
      // if (subscription != null) {
      //   print('Aggiornando database Firebase con le informazioni dell\'abbonamento...');
      //   await updateUserSubscriptionInDatabase(
      //     planType: planType,
      //     subscriptionData: subscription,
      //     paymentMethodId: paymentMethodId,
      //   );
      // }
      
      final result = {
        'success': true,
        'payment_intent_id': paymentIntentId,
        'client_secret': clientSecret,
        'customer_email': customerEmail,
        'subscription': subscription,
        'plan_type': planType,
      };
      
      print('Risultato finale restituito: ${result.toString()}');
      print('Customer ID nel risultato finale: ${(result['subscription'] as Map<String, dynamic>?)?['customer_id']}');
      
      return result;

    } catch (e) {
      print('Errore durante il pagamento: $e');
      
      if (e is StripeException) {
        print('StripeException: ${e.error.code} - ${e.error.message}');
        
        switch (e.error.code) {
          case 'account_invalid':
            // Errore dell'account Stripe
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Errore di configurazione del pagamento. Riprova più tardi.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            break;
          case 'invalid_request_error':
            // Richiesta non valida
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Richiesta di pagamento non valida. Riprova.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            break;
          case 'card_error':
            // Errore della carta
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Errore della carta: ${e.error.message}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            break;
          case 'payment_intent_unexpected_state':
            // Stato del payment intent inaspettato
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Errore nello stato del pagamento. Riprova.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            break;
          case 'canceled':
            // Pagamento annullato dall'utente: non mostrare nulla
            break;
          default:
            // Altri errori Stripe
            // Non mostrare SnackBar generico
            break;
        }
      } else {
        // Altri errori
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Errore: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      
      return null;
    }
  }

  /// Verifica lo stato di un abbonamento
  static Future<Map<String, dynamic>?> verifySubscription({
    required String subscriptionId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_backendUrl/verify-subscription?subscription_id=$subscriptionId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Errore nella verifica dell\'abbonamento: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Errore durante la verifica dell\'abbonamento: $e');
      return null;
    }
  }

  /// Completa un abbonamento dopo il periodo di prova
  static Future<Map<String, dynamic>?> completeSubscription({
    required String subscriptionId,
    String? paymentMethodId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/complete-subscription'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'subscription_id': subscriptionId,
          'payment_method_id': paymentMethodId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['subscription'];
      } else {
        print('Errore nel completamento dell\'abbonamento: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Errore durante il completamento dell\'abbonamento: $e');
      return null;
    }
  }

  /// Riprende un abbonamento in pausa
  static Future<Map<String, dynamic>?> resumeSubscription({
    required String subscriptionId,
    String? paymentMethodId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/resume-subscription'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'subscription_id': subscriptionId,
          'payment_method_id': paymentMethodId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['subscription'];
      } else {
        print('Errore nella ripresa dell\'abbonamento: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Errore durante la ripresa dell\'abbonamento: $e');
      return null;
    }
  }

  /// Crea un abbonamento di trial senza payment method
  /// NOTA: userLocation è opzionale - la localizzazione sarà determinata dall'IP lato server
  static Future<Map<String, dynamic>?> createTrialSubscription({
    required String customerEmail,
    String planType = 'monthly',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/create-trial-subscription'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'customer_email': customerEmail,
          'plan_type': planType,
          // La localizzazione sarà determinata automaticamente dall'IP lato server
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['subscription'];
      } else {
        print('Errore nella creazione dell\'abbonamento di trial: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Errore durante la creazione dell\'abbonamento di trial: $e');
      return null;
    }
  }

  /// Gestisce il webhook di Stripe per aggiornare lo stato dell'abbonamento
  static Future<void> handleWebhook({
    required String eventType,
    required Map<String, dynamic> eventData,
  }) async {
    switch (eventType) {
      case 'payment_intent.succeeded':
        await _handlePaymentIntentSucceeded(eventData);
        break;
      case 'customer.subscription.created':
        await _handleSubscriptionCreated(eventData);
        break;
      case 'customer.subscription.updated':
        await _handleSubscriptionUpdated(eventData);
        break;
      case 'customer.subscription.deleted':
        await _handleSubscriptionDeleted(eventData);
        break;
      case 'customer.subscription.trial_will_end':
        await _handleTrialWillEnd(eventData);
        break;
      case 'customer.subscription.trial_ended':
        await _handleTrialEnded(eventData);
        break;
      case 'customer.subscription.paused':
        await _handleSubscriptionPaused(eventData);
        break;
      case 'customer.subscription.resumed':
        await _handleSubscriptionResumed(eventData);
        break;
      default:
        print('Evento webhook non gestito: $eventType');
    }
  }

  static Future<void> _handlePaymentIntentSucceeded(Map<String, dynamic> eventData) async {
    // Gestisci il pagamento completato
    print('Pagamento completato: ${eventData['id']}');
    // Aggiorna lo stato dell'utente nel database
  }

  static Future<void> _handleSubscriptionCreated(Map<String, dynamic> eventData) async {
    // Gestisci la creazione dell'abbonamento
    print('Abbonamento creato: ${eventData['id']}');
    // await updateSubscriptionStatus(
    //   subscriptionId: eventData['id'],
    //   status: eventData['status'],
    //   planType: eventData['items']?['data']?[0]?['price']?['recurring']?['interval'],
    // );
  }

  static Future<void> _handleSubscriptionUpdated(Map<String, dynamic> eventData) async {
    // Gestisci l'aggiornamento dell'abbonamento
    print('Abbonamento aggiornato: ${eventData['id']}');
    // await updateSubscriptionStatus(
    //   subscriptionId: eventData['id'],
    //   status: eventData['status'],
    // );
  }

  static Future<void> _handleSubscriptionDeleted(Map<String, dynamic> eventData) async {
    // Gestisci la cancellazione dell'abbonamento
    print('Abbonamento cancellato: ${eventData['id']}');
    // await updateSubscriptionStatus(
    //   subscriptionId: eventData['id'],
    //   status: 'canceled',
    // );
  }

  static Future<void> _handleTrialWillEnd(Map<String, dynamic> eventData) async {
    // Gestisci l'avviso che il trial sta per finire (3 giorni prima)
    print('Trial sta per finire: ${eventData['id']}');
    
    try {
      final subscriptionId = eventData['id'];
      final subscription = await verifySubscription(subscriptionId: subscriptionId);
      
      if (subscription != null && subscription['subscription'] != null) {
        final subData = subscription['subscription'];
        final status = subData['status'];
        
        // Se l'abbonamento è ancora in trial, invia una notifica all'utente
        if (status == 'trialing') {
          // Qui puoi inviare una notifica push o email all'utente
          print('Inviando notifica di fine trial per: $subscriptionId');
        }
      }
    } catch (e) {
      print('Errore nella gestione del trial will end: $e');
    }
  }

  static Future<void> _handleTrialEnded(Map<String, dynamic> eventData) async {
    // Gestisci la fine del trial
    print('Trial terminato: ${eventData['id']}');
    
    try {
      final subscriptionId = eventData['id'];
      
      // Completa automaticamente l'abbonamento
      final completedSubscription = await completeSubscription(
        subscriptionId: subscriptionId,
      );
      
      if (completedSubscription != null) {
        print('Abbonamento completato automaticamente dopo la fine del trial: $subscriptionId');
        // await updateSubscriptionStatus(
        //   subscriptionId: subscriptionId,
        //   status: completedSubscription['status'] ?? 'active',
        // );
      } else {
        print('Errore nel completamento automatico dell\'abbonamento: $subscriptionId');
      }
    } catch (e) {
      print('Errore nella gestione del trial ended: $e');
    }
  }

  static Future<void> _handleSubscriptionPaused(Map<String, dynamic> eventData) async {
    // Gestisci la pausa dell'abbonamento (quando il trial finisce senza metodo di pagamento)
    print('Abbonamento in pausa: ${eventData['id']}');
    
    try {
      final subscriptionId = eventData['id'];
      
      // Aggiorna lo stato nel database
      // await updateSubscriptionStatus(
      //   subscriptionId: subscriptionId,
      //   status: 'paused',
      // );
      
      // Qui puoi inviare una notifica all'utente per informarlo che l'abbonamento è in pausa
      // e che deve aggiungere un metodo di pagamento per continuare
      print('Inviando notifica di abbonamento in pausa per: $subscriptionId');
      
    } catch (e) {
      print('Errore nella gestione della pausa abbonamento: $e');
    }
  }

  static Future<void> _handleSubscriptionResumed(Map<String, dynamic> eventData) async {
    // Gestisci la ripresa dell'abbonamento (quando viene aggiunto un metodo di pagamento)
    print('Abbonamento ripreso: ${eventData['id']}');
    // await updateSubscriptionStatus(
    //   subscriptionId: eventData['id'],
    //   status: eventData['status'],
    // );
  }

  /// Calcola le tasse per un importo specifico
  /// DEPRECATO: La tassazione è ora gestita automaticamente da Stripe in base all'IP
  /// Questa funzione è mantenuta per compatibilità ma non è più utilizzata
  static Future<Map<String, dynamic>?> calculateTax({
    required int amount,
    required String currency,
    required Map<String, dynamic> userLocation,
    List<Map<String, dynamic>>? lineItems,
  }) async {
    print('⚠️ calculateTax è deprecato - la tassazione è ora gestita automaticamente da Stripe');
    return null;
  }

  /// Crea una transazione fiscale da un calcolo
  static Future<Map<String, dynamic>?> createTaxTransaction({
    required String calculationId,
    required String reference,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/create-tax-transaction'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'calculation_id': calculationId,
          'reference': reference,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Transazione fiscale creata: ${data.toString()}');
        return data;
      } else {
        print('Errore nella creazione della transazione fiscale: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Errore durante la creazione della transazione fiscale: $e');
      return null;
    }
  }

  /// Recupera il customer ID dall'email dell'utente
  static Future<String?> getCustomerIdFromEmail(String customerEmail) async {
    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/get-customer-id'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'customer_email': customerEmail,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['customer_id'];
      } else {
        print('Errore nel recupero del customer ID: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Errore durante il recupero del customer ID: $e');
      return null;
    }
  }

  /// Aggiorna il database Firebase con le informazioni del piano acquistato
  static Future<void> updateUserSubscriptionInDatabase({
    required String planType,
    required Map<String, dynamic> subscriptionData,
    String? paymentMethodId,
  }) async {
    // Disabilitato: ora la logica di salvataggio è lato server
    print('updateUserSubscriptionInDatabase chiamato, ma ora gestito dal server.');
    return;
  }

  /// Verifica lo stato dell'abbonamento nel database Firebase
  static Future<Map<String, dynamic>?> getUserSubscriptionFromDatabase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('Utente non autenticato, impossibile leggere dal database');
        return null;
      }

      final database = FirebaseDatabase.instance;
      final userRef = database.ref().child('users/users/${user.uid}');
      
      final snapshot = await userRef.get();
      if (snapshot.exists) {
        final userData = snapshot.value as Map<dynamic, dynamic>;
        final subscriptionData = userData['subscription'];
        
        if (subscriptionData != null) {
          return Map<String, dynamic>.from(subscriptionData);
        }
      }
      
      return null;
    } catch (e) {
      print('Errore nella lettura del database: $e');
      return null;
    }
  }

  /// Verifica se l'utente ha un abbonamento premium attivo
  static Future<bool> isUserPremium() async {
    try {
      final subscription = await getUserSubscriptionFromDatabase();
      if (subscription != null) {
        final status = subscription['status'];
        final isPremium = subscription['isPremium'] ?? false;
        
        // Verifica se l'abbonamento è attivo o in trial
        return isPremium && (status == 'active' || status == 'trialing');
      }
      return false;
    } catch (e) {
      print('Errore nella verifica dello stato premium: $e');
      return false;
    }
  }

  /// Aggiorna lo stato dell'abbonamento nel database (per webhook)
  static Future<void> updateSubscriptionStatus({
    required String subscriptionId,
    required String status,
    String? planType,
  }) async {
    // Disabilitato: ora la logica di salvataggio è lato server
    print('updateSubscriptionStatus chiamato, ma ora gestito dal server.');
    return;
  }
} 