import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:viralyst/pages/upgrade_premium_page.dart';
import 'package:viralyst/pages/upgrade_premium_ios_page.dart';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:viralyst/pages/social/instagram_page.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:viralyst/pages/credits_page.dart';

class VideoStatsService {
  // API keys e tokens - da sostituire con i valori reali o meglio ancora, prenderli da un secure storage
  static const String tikTokAccessToken = 'TUO_ACCESS_TOKEN';
  
  // Funzione per salvare i dati delle API nel database Firebase
  Future<void> saveApiStatsToFirebase({
    required String userId,
    required String videoId,
    required String platform,
    required String accountId,
    required Map<String, dynamic> stats,
    required String accountUsername,
    required String accountDisplayName,
  }) async {
    try {
      final databaseRef = FirebaseDatabase.instance.ref();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // Crea il path per salvare i dati: users/users/[uid]/videos/[id]/api_stats/[platform]/[accountId]
      final statsPath = 'users/users/$userId/videos/$videoId/api_stats/$platform/$accountId';
      
      final statsData = {
        'likes': stats['likes'] ?? 0,
        'comments': stats['comments'] ?? 0,
        'views': stats['views'] ?? 0,
        'account_username': accountUsername,
        'account_display_name': accountDisplayName,
        'platform': platform,
        'account_id': accountId,
        'timestamp': timestamp,
        'last_updated': timestamp,
      };
      
      // Salva i dati nel database
      await databaseRef.child(statsPath).set(statsData);
      
      print('[FIREBASE] ✅ Dati API salvati per $platform/$accountId: $statsData');
    } catch (e) {
      print('[FIREBASE] ❌ Errore nel salvataggio dati API per $platform/$accountId: $e');
    }
  }
  
  // Funzione per caricare i dati salvati dal database Firebase
  Future<Map<String, Map<String, dynamic>>> loadApiStatsFromFirebase({
    required String userId,
    required String videoId,
  }) async {
    try {
      final databaseRef = FirebaseDatabase.instance.ref();
      final statsPath = 'users/users/$userId/videos/$videoId/api_stats';
      
      final snapshot = await databaseRef.child(statsPath).get();
      Map<String, Map<String, dynamic>> savedStats = {};
      
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        
        data.forEach((platform, accounts) {
          if (accounts is Map) {
            accounts.forEach((accountId, stats) {
              if (stats is Map) {
                final key = '${platform}_$accountId';
                savedStats[key] = {
                  'likes': stats['likes'] ?? 0,
                  'comments': stats['comments'] ?? 0,
                  'views': stats['views'] ?? 0,
                  'platform': platform,
                  'account_id': accountId,
                  'account_username': stats['account_username'] ?? '',
                  'account_display_name': stats['account_display_name'] ?? '',
                  'timestamp': stats['timestamp'] ?? 0,
                  'last_updated': stats['last_updated'] ?? 0,
                };
              }
            });
          }
        });
      }
      
      print('[FIREBASE] ✅ Dati API caricati per $videoId: ${savedStats.length} record');
      return savedStats;
    } catch (e) {
      print('[FIREBASE] ❌ Errore nel caricamento dati API per $videoId: $e');
      return {};
    }
  }
  
  // Funzione per aggiornare i totali dell'utente con controllo incrementale
  Future<void> updateUserTotals({
    required String userId,
    required String platform,
    required String accountId,
    required Map<String, dynamic> newStats,
    required String accountUsername,
    required String accountDisplayName,
  }) async {
    try {
      final databaseRef = FirebaseDatabase.instance.ref();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // Path per i totali dell'utente
      final userTotalsPath = 'users/users/$userId/totals';
      
      // Path per il tracking delle statistiche per piattaforma/account
      final platformStatsPath = 'users/users/$userId/platform_stats/$platform/$accountId';
      
      // 1. Leggi i totali attuali dell'utente
      final totalsSnapshot = await databaseRef.child(userTotalsPath).get();
      Map<String, dynamic> currentTotals = {};
      
      if (totalsSnapshot.exists) {
        currentTotals = Map<String, dynamic>.from(totalsSnapshot.value as Map<dynamic, dynamic>);
      }
      
      // 2. Leggi le statistiche precedenti per questa piattaforma/account
      final platformStatsSnapshot = await databaseRef.child(platformStatsPath).get();
      Map<String, dynamic> previousStats = {};
      
      if (platformStatsSnapshot.exists) {
        previousStats = Map<String, dynamic>.from(platformStatsSnapshot.value as Map<dynamic, dynamic>);
      }
      
      // 3. Calcola le differenze (solo incrementi positivi)
      int likesDiff = 0;
      int commentsDiff = 0;
      int viewsDiff = 0;
      
      final newLikes = newStats['likes'] ?? 0;
      final newComments = newStats['comments'] ?? 0;
      final newViews = newStats['views'] ?? 0;
      
      final previousLikes = previousStats['likes'] ?? 0;
      final previousComments = previousStats['comments'] ?? 0;
      final previousViews = previousStats['views'] ?? 0;
      
      // Calcola solo gli incrementi positivi
      if (newLikes > previousLikes) {
        likesDiff = newLikes - previousLikes;
      }
      if (newComments > previousComments) {
        commentsDiff = newComments - previousComments;
      }
      if (newViews > previousViews) {
        viewsDiff = newViews - previousViews;
      }
      
      // 4. Aggiorna i totali solo se ci sono incrementi
      if (likesDiff > 0 || commentsDiff > 0 || viewsDiff > 0) {
        final currentTotalLikes = currentTotals['total_likes'] ?? 0;
        final currentTotalComments = currentTotals['total_comments'] ?? 0;
        final currentTotalViews = currentTotals['total_views'] ?? 0;
        
        final updatedTotals = {
          'total_likes': currentTotalLikes + likesDiff,
          'total_comments': currentTotalComments + commentsDiff,
          'total_views': currentTotalViews + viewsDiff,
          'last_updated': timestamp,
        };
        
        // Salva i totali aggiornati
        await databaseRef.child(userTotalsPath).update(updatedTotals);
        
        print('[TOTALS] ✅ Aggiornati totali utente: +$likesDiff likes, +$commentsDiff comments, +$viewsDiff views');
        print('[TOTALS] Nuovi totali: ${updatedTotals['total_likes']} likes, ${updatedTotals['total_comments']} comments, ${updatedTotals['total_views']} views');
      } else {
        print('[TOTALS] ⚠️ Nessun incremento rilevato per $platform/$accountId');
      }
      
      // 5. Salva sempre le statistiche attuali per il confronto futuro
      final currentPlatformStats = {
        'likes': newLikes,
        'comments': newComments,
        'views': newViews,
        'account_username': accountUsername,
        'account_display_name': accountDisplayName,
        'platform': platform,
        'account_id': accountId,
        'timestamp': timestamp,
        'last_updated': timestamp,
      };
      
      await databaseRef.child(platformStatsPath).set(currentPlatformStats);
      
      print('[TOTALS] ✅ Statistiche piattaforma salvate per confronto futuro: $platform/$accountId');
      
    } catch (e) {
      print('[TOTALS] ❌ Errore nell\'aggiornamento totali utente: $e');
    }
  }
  static const String youtubeApiKey = 'AIzaSyDcqQOKXVB2Y-2R73ytvlT9Hww92mD6MEg'; // Android key

  // static const String instagramAccessToken = 'TUO_INSTAGRAM_ACCESS_TOKEN';

  static const String twitterBearerToken = 'AAAAAAAAAAAAAAAAAAAAABSU0QEAAAAAfMR5IAt0vMXdx4ufi%2FjsqhimtnU%3DA4ywPBcwqVy3Aa7zv03HvR6teprbtgu2KdHB3PCPB68V0dMX4o';

  // TikTok API - secondo la documentazione ufficiale
  Future<Map<String, dynamic>> getTikTokStats(String videoId) async {
    try {
      final response = await http.post(
        Uri.parse('https://open-api.tiktok.com/video/list/'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "access_token": tikTokAccessToken,
          "fields": ["id", "like_count", "comment_count", "view_count"]
        })
      );
      
      if (response.statusCode == 200) {
        var json = jsonDecode(response.body);
        // Cerchiamo il video specifico nell'elenco dei video
        var videos = json['data']['videos'] as List;
        for (var video in videos) {
          if (video['id'] == videoId) {
            return {
              'likes': video['like_count'],
              'comments': video['comment_count'],
              'views': video['view_count']
            };
          }
        }
        throw Exception('Video non trovato nei risultati');
      } else {
        throw Exception('Failed to load TikTok stats: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching TikTok stats: $e');
    }
  }

  // YouTube API - secondo la documentazione ufficiale
  Future<Map<String, dynamic>> getYouTubeStats(String videoId, String? accessToken) async {
    try {
      String? token = accessToken;
      
      // Se non è fornito un access token, prova a ottenerlo tramite Google Sign-In
      if (token == null) {
        print('[YOUTUBE STATS] Nessun access token fornito, tentativo di autenticazione Google Sign-In...');
        
        // Initialize Google Sign-In
        final GoogleSignIn googleSignIn = GoogleSignIn(
          scopes: [
            'https://www.googleapis.com/auth/youtube.readonly',
            'https://www.googleapis.com/auth/youtube'
          ],
          clientId: '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com',
          signInOption: SignInOption.standard,
        );
        
        print('[YOUTUBE STATS] Google Sign-In inizializzato con client ID: ${googleSignIn.clientId}');
        print('[YOUTUBE STATS] Scopes configurati: ${googleSignIn.scopes}');
        
        try {
          // Prova prima il sign-in silenzioso
          print('[YOUTUBE STATS] Tentativo sign-in silenzioso...');
          final GoogleSignInAccount? googleUser = await googleSignIn.signInSilently();
          
          if (googleUser == null) {
            print('[YOUTUBE STATS] Sign-in silenzioso fallito, tentativo sign-in normale...');
            // Se il sign-in silenzioso fallisce, prova il sign-in normale
            final GoogleSignInAccount? newGoogleUser = await googleSignIn.signIn();
            if (newGoogleUser == null) {
              print('[YOUTUBE STATS] ❌ Sign-in normale annullato dall\'utente');
              throw Exception('Accesso Google annullato o fallito');
            }
            print('[YOUTUBE STATS] ✅ Sign-in normale completato');
          } else {
            print('[YOUTUBE STATS] ✅ Sign-in silenzioso completato');
          }
          
          print('[YOUTUBE STATS] Account Google: ${googleUser!.email}');
          print('[YOUTUBE STATS] Display name: ${googleUser.displayName}');
          
          // Get authentication details
          print('[YOUTUBE STATS] Recupero dettagli autenticazione...');
          final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
          
          print('[YOUTUBE STATS] Access token presente: ${googleAuth.accessToken != null}');
          print('[YOUTUBE STATS] ID token presente: ${googleAuth.idToken != null}');
          
          if (googleAuth.accessToken == null) {
            print('[YOUTUBE STATS] ❌ Access token null dopo autenticazione');
            throw Exception('Impossibile ottenere il token di accesso Google');
          }
          
          token = googleAuth.accessToken;
          print('[YOUTUBE STATS] ✅ Access token ottenuto tramite Google Sign-In');
          print('[YOUTUBE STATS] ✅ Token preview: ${token!.substring(0, 10)}...');
          print('[YOUTUBE STATS] ✅ Lunghezza token: ${token!.length} caratteri');
          
        } catch (e) {
          print('[YOUTUBE STATS] ❌ Errore durante l\'autenticazione Google Sign-In: $e');
          print('[YOUTUBE STATS] 🔄 Fallback all\'API key...');
          // Fallback all'API key se l'autenticazione fallisce
        }
      } else {
        print('[YOUTUBE STATS] ✅ Access token fornito dal database');
        print('[YOUTUBE STATS] ✅ Token preview: ${token.substring(0, 10)}...');
        print('[YOUTUBE STATS] ✅ Lunghezza token: ${token.length} caratteri');
      }
      
      Uri url;
      Map<String, String> headers = {};
      
      if (token != null) {
        // Usa l'access token per l'autenticazione OAuth
        url = Uri.parse('https://www.googleapis.com/youtube/v3/videos'
            '?part=statistics,contentDetails'
            '&id=$videoId');
        headers['Authorization'] = 'Bearer $token';
        print('[YOUTUBE STATS] 🔐 Usando OAuth access token per l\'autenticazione');
        print('[YOUTUBE STATS] 🔐 Metodo autenticazione: OAuth Bearer Token');
      } else {
        // Fallback all'API key
        url = Uri.parse('https://www.googleapis.com/youtube/v3/videos'
            '?part=statistics,contentDetails'
            '&id=$videoId'
            '&key=$youtubeApiKey');
        print('[YOUTUBE STATS] 🔑 Usando API key per l\'autenticazione');
        print('[YOUTUBE STATS] 🔑 Metodo autenticazione: API Key');
      }
      
      print('[YOUTUBE STATS] 📡 URL chiamata: $url');
      print('[YOUTUBE STATS] 📡 Headers: $headers');
      print('[YOUTUBE STATS] 📡 Video ID: $videoId');
      
      final response = await http.get(url, headers: headers);
      
      print('[YOUTUBE STATS] 📡 Status code: ${response.statusCode}');
      print('[YOUTUBE STATS] 📡 Response headers: ${response.headers}');
      print('[YOUTUBE STATS] 📡 Response body: ${response.body}');
      
      if (response.statusCode != 200) {
        print('[YOUTUBE STATS] ❌ Errore API: ${response.statusCode}');
        print('[YOUTUBE STATS] ❌ Errore dettagliato: ${response.body}');
      } else {
        print('[YOUTUBE STATS] ✅ Chiamata API riuscita');
      }
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['items'] != null && data['items'].isNotEmpty) {
          final stats = data['items'][0]['statistics'];
          return {
            'likes': int.parse(stats['likeCount'] ?? '0'),
            'comments': int.parse(stats['commentCount'] ?? '0'),
            'views': int.parse(stats['viewCount'] ?? '0')
          };
        } else {
          throw Exception('YouTube video not found');
        }
      } else {
        throw Exception('Failed to load YouTube stats: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching YouTube stats: $e');
    }
  }

  // Instagram API - secondo la documentazione ufficiale
  Future<Map<String, dynamic>> getInstagramStats(String mediaId, String accessToken) async {
    try {
      // Prima richiesta: ottenere like e commenti
      final url1 = Uri.parse('https://graph.facebook.com/v14.0/$mediaId'
          '?fields=like_count,comments_count'
          '&access_token=$accessToken');
      print('[INSTAGRAM STATS] GET like/comment URL: ' + url1.toString());
      print('[INSTAGRAM STATS] AccessToken: ' + accessToken);
      final response1 = await http.get(url1);
      if (response1.statusCode != 200) {
        throw Exception('Failed to load Instagram stats: \u001b[1m${response1.statusCode}\u001b[0m');
      }
      final data = jsonDecode(response1.body);
      int likes = data['like_count'] ?? 0;
      int comments = data['comments_count'] ?? 0;
      // Seconda richiesta: ottenere visualizzazioni video (se applicabile)
      final url2 = Uri.parse('https://graph.facebook.com/v14.0/$mediaId/insights'
          '?metric=video_views'
          '&access_token=$accessToken');
      print('[INSTAGRAM STATS] GET views URL: ' + url2.toString());
      final response2 = await http.get(url2);
      int views = 0;
      if (response2.statusCode == 200) {
        final insightsData = jsonDecode(response2.body);
        print('[INSTAGRAM STATS] RESPONSE BODY (views): ${response2.body}');
        if (insightsData['data'] != null && insightsData['data'].isNotEmpty) {
          for (final metric in insightsData['data']) {
            if (metric['name'] == 'video_views' && metric['values'] != null) {
              for (final v in metric['values']) {
                final value = v['value'];
                if (value != null) {
                  int? parsed;
                  if (value is int) {
                    parsed = value;
                  } else if (value is String) {
                    parsed = int.tryParse(value);
                  }
                  if (parsed != null && parsed > views) {
                    views = parsed;
                  }
                }
              }
            }
          }
        }
      } else {
        print('[INSTAGRAM STATS] RESPONSE ERROR (views): ${response2.statusCode} - ${response2.body}');
      }
      print('[INSTAGRAM STATS] FINAL VIEWS VALUE: $views');
      return {
        'likes': likes,
        'comments': comments,
        'views': views
      };
    } catch (e) {
      print('[INSTAGRAM STATS] ERROR: $e');
      throw Exception('Error fetching Instagram stats: $e');
    }
  }

  // Facebook API - secondo la documentazione ufficiale
  Future<Map<String, dynamic>> getFacebookStats(String videoId, String accessToken) async {
    try {
      // Per i video, usa l'endpoint video_insights
      final videoInsightsUrl = Uri.parse('https://graph.facebook.com/v23.0/$videoId/video_insights'
          '?metric=post_video_views,post_video_views_unique'
          '&access_token=$accessToken');
          
      final videoResponse = await http.get(videoInsightsUrl);
      
      print('[FACEBOOK API] Video Insights URL: $videoInsightsUrl');
      print('[FACEBOOK API] Video Insights Status: ${videoResponse.statusCode}');
      print('[FACEBOOK API] Video Insights Response: ${videoResponse.body}');
      
        int views = 0;
        
      if (videoResponse.statusCode == 200) {
        final videoData = jsonDecode(videoResponse.body);
        
        if (videoData['data'] != null) {
          for (var metric in videoData['data']) {
            if (metric['name'] == 'post_video_views') {
              views = metric['values'][0]['value'] ?? 0;
            }
          }
        }
      }
      
      // Per like e commenti, usa l'endpoint normale del video
      final videoUrl = Uri.parse('https://graph.facebook.com/v23.0/$videoId'
          '?fields=likes.summary(true),comments.summary(true)'
          '&access_token=$accessToken');
          
      final response = await http.get(videoUrl);
      
      print('[FACEBOOK API] Video URL: $videoUrl');
      print('[FACEBOOK API] Video Status: ${response.statusCode}');
      print('[FACEBOOK API] Video Response: ${response.body}');
      
      int likes = 0;
      int comments = 0;
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        likes = data['likes']?['summary']?['total_count'] ?? 0;
        comments = data['comments']?['summary']?['total_count'] ?? 0;
        }
        
        return {
          'likes': likes,
          'comments': comments,
          'views': views
        };
    } catch (e) {
      throw Exception('Error fetching Facebook stats: $e');
    }
  }

  // Twitter/X API - secondo la documentazione ufficiale e la struttura Firebase
  Future<Map<String, dynamic>> getTwitterStats({
    required String userId,
    required String videoId,
  }) async {
    try {
      final databaseRef = FirebaseDatabase.instance.ref();
      print('[TWITTER] 🔍 Cerco accounts Twitter per video: users/users/[36m$userId[0m/videos/[36m$videoId[0m/accounts/Twitter');
      final accountsSnapshot = await databaseRef.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Twitter').get();
      if (!accountsSnapshot.exists) {
        print('[TWITTER] ❌ Twitter account info not found for this video');
        throw Exception('Twitter account info not found for this video');
      }
      final dynamic rawAccounts = accountsSnapshot.value;
      List<dynamic> accountsList;
      if (rawAccounts is List) {
        accountsList = rawAccounts;
      } else if (rawAccounts is Map) {
        accountsList = (rawAccounts as Map).values.toList();
      } else {
        accountsList = const [];
      }
      if (accountsList.isEmpty) {
        print('[TWITTER] ❌ No Twitter account linked to this video');
        throw Exception('No Twitter account linked to this video');
      }
      final accountData = accountsList[0] as Map<dynamic, dynamic>;
      final twitterProfileId = accountData['id']?.toString();
      final twitterPostId = accountData['post_id']?.toString();
      print('[TWITTER] ✅ Estratti profileId: [36m$twitterProfileId[0m, postId: [36m$twitterPostId[0m');
      if (twitterProfileId == null || twitterProfileId.isEmpty || twitterPostId == null || twitterPostId.isEmpty) {
        print('[TWITTER] ❌ Twitter profile ID or post ID missing');
        throw Exception('Twitter profile ID or post ID missing');
      }
      // Recupera access_token dal path users/users/[uid]/social_accounts/twitter/[idprofilotwitter]/access_token
      print('[TWITTER] 🔍 Cerco access token: users/users/[36m$userId[0m/social_accounts/twitter/[36m$twitterProfileId[0m/access_token');
      final tokenSnapshot = await databaseRef.child('users').child('users').child(userId).child('social_accounts').child('twitter').child(twitterProfileId).child('access_token').get();
      if (!tokenSnapshot.exists) {
        print('[TWITTER] ❌ Twitter access token not found');
        throw Exception('Twitter access token not found');
      }
      final accessToken = tokenSnapshot.value.toString();
      print('[TWITTER] ✅ Access token trovato, preview: [32m${accessToken.substring(0, 8)}...[0m');
      // Unica richiesta combinata: public_metrics + media public_metrics
      final url = Uri.parse('https://api.twitter.com/2/tweets/$twitterPostId?tweet.fields=public_metrics,organic_metrics,non_public_metrics,entities&expansions=attachments.media_keys&media.fields=public_metrics,organic_metrics,non_public_metrics');
      print('[TWITTER] 📡 GET $url');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      print('[TWITTER] 📡 Status code: [33m${response.statusCode}[0m');
      print('[TWITTER] 📡 Response body: ${response.body}');
      int likes = 0;
      int replies = 0;
      int retweets = 0;
      int quotes = 0;
      int impressions = 0;
      int videoViews = 0;
      int urlClicks = 0;
      int profileClicks = 0;
      int playback0 = 0, playback25 = 0, playback50 = 0, playback75 = 0, playback100 = 0;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tweet = data['data'];
        // Public metrics
        final metrics = tweet['public_metrics'] ?? {};
        likes = metrics['like_count'] ?? 0;
        replies = metrics['reply_count'] ?? 0;
        retweets = metrics['retweet_count'] ?? 0;
        quotes = metrics['quote_count'] ?? 0;
        // Organic/Non-public metrics (se disponibili)
        final organic = tweet['organic_metrics'] ?? {};
        final nonPublic = tweet['non_public_metrics'] ?? {};
        impressions = organic['impression_count'] ?? nonPublic['impression_count'] ?? 0;
        urlClicks = organic['url_link_clicks'] ?? nonPublic['url_link_clicks'] ?? 0;
        profileClicks = organic['user_profile_clicks'] ?? nonPublic['user_profile_clicks'] ?? 0;
        // Media metrics (video)
        if (data['includes'] != null && data['includes']['media'] != null) {
          final mediaList = data['includes']['media'] as List<dynamic>;
          for (final media in mediaList) {
            if (media['type'] == 'video') {
              final mediaPublic = media['public_metrics'] ?? {};
              final mediaOrganic = media['organic_metrics'] ?? {};
              final mediaNonPublic = media['non_public_metrics'] ?? {};
              videoViews = mediaPublic['view_count'] ?? mediaOrganic['view_count'] ?? 0;
              playback0 = mediaNonPublic['playback_0_count'] ?? mediaOrganic['playback_0_count'] ?? 0;
              playback25 = mediaNonPublic['playback_25_count'] ?? mediaOrganic['playback_25_count'] ?? 0;
              playback50 = mediaNonPublic['playback_50_count'] ?? mediaOrganic['playback_50_count'] ?? 0;
              playback75 = mediaNonPublic['playback_75_count'] ?? mediaOrganic['playback_75_count'] ?? 0;
              playback100 = mediaNonPublic['playback_100_count'] ?? mediaOrganic['playback_100_count'] ?? 0;
              break;
            }
          }
        }
      } else {
        print('[TWITTER] ❌ Failed to load Twitter metrics: \\${response.statusCode}');
        throw Exception('Failed to load Twitter metrics: \\${response.statusCode}');
      }
      // Scegli la metrica views migliore disponibile
      int views = videoViews > 0 ? videoViews : (impressions > 0 ? impressions : (retweets + replies));
      print('[TWITTER] ✅ Risultato finale: likes=$likes, replies=$replies, retweets=$retweets, quotes=$quotes, impressions=$impressions, videoViews=$videoViews, urlClicks=$urlClicks, profileClicks=$profileClicks, quartili=[$playback0,$playback25,$playback50,$playback75,$playback100], views=$views');
      return {
        'likes': likes,
        'comments': replies,
        'views': views,
        'retweets': retweets,
        'quotes': quotes,
        'impressions': impressions,
        'video_views': videoViews,
        'url_clicks': urlClicks,
        'profile_clicks': profileClicks,
        'playback_0': playback0,
        'playback_25': playback25,
        'playback_50': playback50,
        'playback_75': playback75,
        'playback_100': playback100,
      };
    } catch (e) {
      print('[TWITTER] ❌ Error fetching Twitter stats: $e');
      throw Exception('Error fetching Twitter stats: $e');
    }
  }

  // Threads API - secondo la documentazione ufficiale
  Future<Map<String, dynamic>> getThreadsStats(String postId, String accessToken) async {
    try {
      final url = Uri.parse('https://graph.threads.net/v1.0/$postId/insights'
          '?metric=views,likes,replies,reposts,quotes'
          '&access_token=$accessToken');
          
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        int likes = 0;
        int replies = 0;
        int views = 0;
        
        if (data['data'] != null) {
          for (var metric in data['data']) {
            if (metric['name'] == 'likes') {
              likes = metric['values'][0]['value'] ?? 0;
            } else if (metric['name'] == 'replies') {
              replies = metric['values'][0]['value'] ?? 0;
            } else if (metric['name'] == 'views') {
              views = metric['values'][0]['value'] ?? 0;
            }
          }
        }
        
        return {
          'likes': likes,
          'comments': replies,
          'views': views
        };
      } else {
        throw Exception('Failed to load Threads stats: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching Threads stats: $e');
    }
  }
}
class ChatGptService {
  static const String apiKey = '';
  static const String apiUrl = 'https://api.openai.com/v1/chat/completions';

  // Funzione per calcolare i token utilizzati
  int _calculateTokens(String text) {
    // Stima approssimativa: 1 token ≈ 4 caratteri per l'inglese, 3 caratteri per altre lingue
    // Questa è una stima conservativa basata sulla documentazione OpenAI
    return (text.length / 4).ceil();
  }

  // RIMOSSO: controllo limiti token (si usa il conteggio analisi giornaliere)

  // Funzione per registrare un'analisi (senza token) nel database Firebase
  Future<void> _saveTokenUsage({
    required String userId,
    required String videoId,
    required int promptTokens,
    required int completionTokens,
    required int totalTokens,
    required String analysisType, // 'initial' o 'chat'
  }) async {
    try {
      final databaseRef = FirebaseDatabase.instance.ref();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // Path per salvare i token: users/users/[uid]/token_usage/[videoId]/[timestamp]
      final tokenPath = 'users/users/$userId/token_usage/$videoId/$timestamp';
      
      final tokenData = {
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'total_tokens': totalTokens,
        'analysis_type': analysisType,
        'timestamp': timestamp,
        'date': DateTime.now().toIso8601String(),
      };
      
      // Salva i dati nel database
      await databaseRef.child(tokenPath).set(tokenData);
      
      // Aggiorna anche il totale dei token per l'utente
      final userTotalsPath = 'users/users/$userId/token_totals';
      final totalsSnapshot = await databaseRef.child(userTotalsPath).get();
      
      Map<String, dynamic> currentTotals = {};
      if (totalsSnapshot.exists) {
        currentTotals = Map<String, dynamic>.from(totalsSnapshot.value as Map<dynamic, dynamic>);
      }
      
      final updatedTotals = {
        // RIMOSSO: total_tokens_used perché non più usato per gating
        'total_analyses': (currentTotals['total_analyses'] ?? 0) + 1,
        'last_updated': timestamp,
      };
      
      await databaseRef.child(userTotalsPath).update(updatedTotals);
      
      // Aggiorna anche l'uso giornaliero
      final today = DateTime.now().toIso8601String().split('T')[0];
      final dailyUsagePath = 'users/users/$userId/daily_analysis_stats/$today';
      final dailySnapshot = await databaseRef.child(dailyUsagePath).get();
      
      Map<String, dynamic> currentDaily = {};
      if (dailySnapshot.exists) {
        currentDaily = Map<String, dynamic>.from(dailySnapshot.value as Map<dynamic, dynamic>);
      }
      
      final updatedDaily = {
        'analysis_count': (currentDaily['analysis_count'] ?? 0) + 1,
        'date': today,
        'last_updated': timestamp,
      };
      
      await databaseRef.child(dailyUsagePath).set(updatedDaily);
      
      print('[AI] ✅ Analisi registrata: ${updatedTotals['total_analyses']} totali, daily count: ${updatedDaily['analysis_count']}');
    } catch (e) {
      print('[AI] ❌ Errore nel salvataggio analisi giornaliere: $e');
    }
  }

  Future<String> analyzeVideoStats(
    Map<String, dynamic> video,
    Map<String, Map<String, double>> statsData,
    String language,
    [Map<String, Map<String, dynamic>>? accountMeta,
     Map<String, Map<String, int>>? manualStats,
     String? customPrompt,
     String? analysisType = 'initial',
     bool isPremium = false]
  ) async {
    try {
      // Costruisci il prompt dinamicamente
      String prompt = customPrompt ?? _buildPrompt(video, statsData, language, accountMeta, manualStats);
      
      // RIMOSSO: gating basato sui token. Ora si controlla solo il numero di analisi giornaliere lato UI prima dell'avvio
      
      // Prepara la richiesta
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {'role': 'user', 'content': prompt}
          ]
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final completion = data['choices'][0]['message']['content'];
        
        // RIMOSSO: salvataggio usage token. Manteniamo solo il log di completamento semplice
        print('[AI] ✅ Analisi completata');
        
        return completion;
      } else {
        throw Exception('Failed to get AI analysis: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error analyzing video stats: $e');
    }
  }

  String _buildPrompt(
    Map<String, dynamic> video,
    Map<String, Map<String, double>> statsData,
    String language,
    [Map<String, Map<String, dynamic>>? accountMeta,
     Map<String, Map<String, int>>? manualStats]
  ) {
    // Formatta la data di pubblicazione
    String publishDate = 'N/A';
    DateTime? date;
    
    if (video['publish_date'] != null) {
      try {
        date = DateTime.parse(video['publish_date']);
        publishDate = DateFormat('yyyy-MM-dd HH:mm').format(date);
      } catch (e) {
        publishDate = video['publish_date'].toString();
      }
    } else if (video['date'] != null) {
      publishDate = video['date'].toString();
      try {
        final parsedDate = DateFormat('dd/MM/yyyy HH:mm').parse(publishDate);
        date = parsedDate;
        publishDate = DateFormat('yyyy-MM-dd HH:mm').format(parsedDate);
      } catch (e) {}
    }

    String timeAgo = 'N/A';
    if (date != null) {
      final now = DateTime.now();
      final difference = now.difference(date);
      if (difference.inDays > 0) {
        timeAgo = '${difference.inDays} giorni fa';
      } else if (difference.inHours > 0) {
        timeAgo = '${difference.inHours} ore fa';
      } else {
        timeAgo = '${difference.inMinutes} minuti fa';
      }
    }

    String generalDescription = video['description'] ?? 'Non disponibile';

    // AGGIUNTA: data attuale in minuti e formato leggibile
    final now = DateTime.now();
    final nowMinutes = now.millisecondsSinceEpoch ~/ 60000;
    final nowFormatted = DateFormat('yyyy-MM-dd HH:mm').format(now);

    String prompt = '''
IMPORTANT: Answer EXCLUSIVELY and MANDATORILY in the following language: "$language".

Objective: Analyze video performance using the data provided (date and time of publication, likes, views, comments), broken down by social platform.

Don't give generic advice: evaluate the data analytically, identifying patterns, anomalies, weaknesses, and strengths. Compare content, timing, and platforms. Focus on the actual effectiveness of the content posted, deducing what works and what doesn't.

Follow this precise structure:

Analyze how date and time affect performance (highlight times or days that bring better or worse results).

Compare performance across different platforms: highlight which content performs best where and why.

Evaluate the strengths of the content based on actual engagement (like/view ratio, comment/view ratio, etc.).

Identify specific weaknesses: where traffic is lost, what does not generate interactions, differences between similar content

Suggest concrete and specific improvements for each platform: what to change in content, style, timing, or format

Propose precise future publishing strategies based on historical data (e.g., "between 6 and 8 p.m. on Instagram brings twice as many comments as other times")

Bonus: indicate at least one little-known trick to improve visibility on each platform, relevant to the content analyzed

IMPORTANT:

DO NOT start with introductory phrases such as "Here is the analysis"

DO NOT include generic comments such as "consistency is important" or "use relevant hashtags"

Write in short paragraphs, visually separated for easy reading

Use bullet points where useful

End with: "Note: This AI analysis is based on available data and trends. Results may vary based on algorithm changes and other factors."

Do not confuse twitter with threads (sometimes you confuse twitter with threads)

IMPORTANT: After your analysis, provide exactly 3 follow-up questions that users might want to ask about this analysis. Format them as:
SUGGESTED_QUESTIONS:
1. [First question]
2. [Second question] 
3. [Third question]

These questions should be relevant to the analysis and help users dive deeper into specific aspects.
''';

    prompt += '\n\nVideo details:';
    prompt += '\nTitle: \'${video['title'] ?? 'Non disponibile'}\'';
    prompt += '\nDescription: $generalDescription';
    prompt += '\nPublish date and time: $publishDate ($timeAgo)';
    prompt += '\nCurrent date and time: $nowFormatted (minutes since epoch: $nowMinutes)';
    prompt += '\n';

    // Raggruppa i dati per piattaforma
    Map<String, List<String>> platformAccounts = {};
    statsData.forEach((metric, platforms) {
      platforms.forEach((accountKey, value) {
        String platform = '';
        final lower = accountKey.toLowerCase();
        if (lower.startsWith('tiktok')) platform = 'tiktok';
        else if (lower.startsWith('youtube')) platform = 'youtube';
        else if (lower.startsWith('instagram')) platform = 'instagram';
        else if (lower.startsWith('facebook')) platform = 'facebook';
        else if (lower.startsWith('threads')) platform = 'threads';
        else if (lower.startsWith('twitter')) platform = 'twitter';
        if (platform.isNotEmpty) {
          platformAccounts.putIfAbsent(platform, () => <String>[]);
          if (!platformAccounts[platform]!.contains(accountKey)) {
            platformAccounts[platform]!.add(accountKey);
          }
        }
      });
    });

    // Ordina le piattaforme per nome
    final orderedPlatforms = [
      'tiktok', 'youtube', 'instagram', 'facebook', 'threads', 'twitter'
    ].where((p) => platformAccounts.containsKey(p)).toList();

    for (final platform in orderedPlatforms) {
      prompt += '\n\n$platform:';
      final accounts = platformAccounts[platform]!;
      // Ordina per display_name se disponibile
      accounts.sort((a, b) {
        String metaA = a;
        String metaB = b;
        if (accountMeta != null) {
          final displayA = accountMeta[a]?['display_name'];
          final displayB = accountMeta[b]?['display_name'];
          if (displayA != null && displayA.toString().isNotEmpty) metaA = displayA.toString();
          if (displayB != null && displayB.toString().isNotEmpty) metaB = displayB.toString();
        }
        return metaA.compareTo(metaB);
      });
      for (final accountKey in accounts) {
        final meta = accountMeta != null ? accountMeta[accountKey] : null;
        final displayName = meta?['display_name'] ?? accountKey;
        final username = meta?['username'] ?? '';
        final description = meta?['description'] ?? '';
        final followers = meta?['followers_count'] ?? 0;
        final platformType = (meta?['platform'] ?? '').toString().toLowerCase();
        final isIGNoToken = platformType == 'instagram' && manualStats != null && manualStats[accountKey] != null;
        prompt += '\n  Account: $displayName';
        if (username != '') prompt += ' (username: $username)';
        if (description != '') prompt += '\n    Description: $description';
        if (followers != 0) prompt += '\n    Followers: $followers';
        // Mostra tutte le metriche disponibili per questo account
        for (final metric in ['likes', 'views', 'comments']) {
          double? value;
          if (isIGNoToken) {
            // Usa manualStats per IG senza token
            value = manualStats![accountKey]?[metric]?.toDouble() ?? 0;
          } else if (metric == 'views' && accountMeta != null) {
            if ((platformType == 'instagram' || platformType == 'facebook' || platformType == 'threads') && manualStats != null && manualStats[accountKey]?['views'] != null) {
              value = manualStats[accountKey]?['views']?.toDouble() ?? 0;
            } else {
              value = statsData[metric]?[accountKey];
            }
          } else {
            value = statsData[metric]?[accountKey];
          }
          if (value != null) {
            prompt += '\n    $metric: \u001b[1m${value.toInt()}\u001b[0m';
          }
        }
      }
    }

    return prompt;
  }
}

class VideoStatsPage extends StatefulWidget {
  final Map<String, dynamic> video;
  
  const VideoStatsPage({
    Key? key,
    required this.video,
  }) : super(key: key);
  
  @override
  State<VideoStatsPage> createState() => _VideoStatsPageState();
}
class _VideoStatsPageState extends State<VideoStatsPage> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  late TabController _tabController;
  int _currentPage = 0;
  bool _isLoading = false;
  bool _isAnalyzing = false;
  final VideoStatsService _statsService = VideoStatsService();
  final ChatGptService _chatGptService = ChatGptService();
  bool _isPremium = false; // Track if user is premium
  bool _hasUsedTrial = false; // Track if user has used the 3-day free trial
  bool _hasDailyAnalysisAvailable = true; // Track if non-premium user has daily analysis available
  final ValueNotifier<String?> _analysisNotifier = ValueNotifier<String?>(null);
  // Credits gating (mirror trends_page)
  int _userCredits = 0;
  bool _showInsufficientCreditsSnackbar = false;
  StreamSubscription<DatabaseEvent>? _creditsSubscription;
  
  // Real data storage
  Map<String, Map<String, double>> _statsData = {
    'likes': <String, double>{},
    'views': <String, double>{},
    'comments': <String, double>{},
  };

  // Nuova mappa per metadati account (profile_image_url, display_name, ecc.)
  Map<String, Map<String, dynamic>> _accountMeta = {};

  // Stato per views manuali
  Map<String, int> _manualViews = {};
  // Stato per likes e comments manuali (nuovo)
  Map<String, int> _manualLikes = {};
  Map<String, int> _manualComments = {};

  // Error handling
  String? _errorMessage;

  // Platform colors
  final Map<String, Color> _platformColors = {
    'tiktok': const Color(0xFF000000),
    'youtube': const Color(0xFFFF0000),
    'instagram': const Color(0xFFE1306C),
    'threads': const Color(0xFF101010),
    'facebook': const Color(0xFF1877F2),
    'twitter': const Color(0xFF1DA1F2),
  };

  @override
  void initState() {
    super.initState();
    _chatScrollController = ScrollController();
    // Ascolta gli scroll per aggiornare la visibilità del bottone "Bottom"
    _chatScrollController.addListener(_onChatScroll);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentPage = _tabController.index;
        });
        _pageController.animateToPage(
          _tabController.index,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
        );
      }
    });
    

    
    _loadStatsData();
    _checkPremiumStatus();
    _loadHasUsedTrial();
    _loadChatGptAnalysis(); // <--- aggiunto caricamento risposta chatgpt
    _loadDailyAnalysisStatus(); // <--- aggiunto caricamento stato analisi giornaliere
    _loadUserProfileImage(); // <--- aggiunto caricamento immagine profilo
    _loadChatMessagesFromFirebase(); // <--- aggiunto caricamento messaggi chat
    _initializeChatMessagesStream(); // <--- aggiunto inizializzazione stream chat
    _loadUserCredits(); // carica i crediti utente
    _initializeCreditsStream(); // ascolta aggiornamenti live dei crediti
  }

  // Carica l'immagine profilo dell'utente da Firebase
  Future<void> _loadUserProfileImage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final snapshot = await databaseRef.child('users').child('users').child(user.uid).child('profile').child('profileImageUrl').get();
        print('DEBUG: Profile image path: users/users/${user.uid}/profile/profileImageUrl');
        print('DEBUG: Snapshot exists: ${snapshot.exists}');
        print('DEBUG: Snapshot value: ${snapshot.value}');
        if (snapshot.exists && snapshot.value is String) {
          setState(() {
            _userProfileImageUrl = snapshot.value as String;
          });
          print('DEBUG: Profile image URL loaded: $_userProfileImageUrl');
        } else {
          print('DEBUG: No profile image found or invalid value');
        }
      }
    } catch (e) {
      print('Error loading user profile image: $e');
    }
  }

  // Carica la risposta chatgpt da Firebase
  Future<void> _loadChatGptAnalysis() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
      if (user != null && videoId != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final snapshot = await databaseRef.child('users').child('users').child(user.uid).child('videos').child(videoId).child('chatgpt').get();
        if (snapshot.exists) {
          if (snapshot.value is String) {
            setState(() {
              _lastAnalysis = fixEncoding(snapshot.value as String);
              _lastAnalysisTimestampMinutes = null;
            });
          } else if (snapshot.value is Map) {
            final map = Map<String, dynamic>.from(snapshot.value as Map);
            final text = map['text'] != null ? fixEncoding(map['text'] as String) : null;
            final timestampMinutes = map['timestamp_minutes'] is int ? map['timestamp_minutes'] as int : int.tryParse(map['timestamp_minutes']?.toString() ?? '');
            
            // Carica le domande suggerite se presenti
            List<String>? suggestedQuestions;
            if (map['suggested_questions'] != null && map['suggested_questions'] is List) {
              suggestedQuestions = (map['suggested_questions'] as List).cast<String>().map((q) => fixEncoding(q)).toList();
            }
            
            setState(() {
              // Aggiorna solo lo stato dell'ultima analisi, senza creare messaggi chat qui
              _lastAnalysis = text;
              _lastAnalysisTimestampMinutes = timestampMinutes;
            });
          }
        }
      }
    } catch (e) {
      print('Errore caricamento chatgpt analysis da Firebase: $e');
    }
  }

  Future<void> _loadHasUsedTrial() async {
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
          });
        }
      }
    } catch (e) {
      print('Errore nel caricamento del trial: $e');
    }
  }

  // Check if the user is premium
  Future<void> _checkPremiumStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final snapshot = await databaseRef.child('users').child('users').child(user.uid).child('isPremium').get();
        setState(() {
          _isPremium = (snapshot.value as bool?) ?? false;
        });
        print('DEBUG: Premium status: $_isPremium');
      }
    } catch (e) {
      print('Error checking premium status: $e');
    }
  }

  // Carica lo stato delle analisi giornaliere per utenti non premium
  Future<void> _loadDailyAnalysisStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final today = DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
        
        final dailyStatsRef = databaseRef.child('users').child('users').child(user.uid).child('daily_analysis_stats');
        final todayRef = dailyStatsRef.child(today);
        
        final snapshot = await todayRef.get();
        
        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          final analysisCount = data['analysis_count'] as int? ?? 0;
          setState(() {
            _hasDailyAnalysisAvailable = analysisCount < 5; // Limite di 5 analisi al giorno
          });
        } else {
          setState(() {
            _hasDailyAnalysisAvailable = true; // Nessun record per oggi, può usare l'analisi
          });
        }
        print('DEBUG: Daily analysis available: $_hasDailyAnalysisAvailable');
      }
    } catch (e) {
      print('Errore nel caricamento dello stato analisi giornaliere: $e');
      setState(() {
        _hasDailyAnalysisAvailable = false; // In caso di errore, non permettere l'uso
      });
    }
  }

  // Carica i crediti dell'utente
  Future<void> _loadUserCredits() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final creditsRef = databaseRef.child('users').child('users').child(user.uid).child('credits');
        final snapshot = await creditsRef.get();
        int currentCredits = 0;

        if (snapshot.exists && snapshot.value != null) {
          if (snapshot.value is int) {
            currentCredits = snapshot.value as int;
          } else if (snapshot.value is String) {
            currentCredits = int.tryParse(snapshot.value as String) ?? 0;
          }
        }

        if (mounted) {
          setState(() {
            _userCredits = currentCredits;
          });
        }
      }
    } catch (e) {
      // ignore load error
    }
  }

  // Sottrae 20 crediti per utenti non premium, mostra snackbar se insufficienti
  Future<bool> _subtractCreditsIfNeeded() async {
    if (_isPremium) return true;
    if (_userCredits < 20) {
      // Non mostrare automaticamente: sarà mostrato solo su tap input, invio o suggested question
      return false;
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final creditsRef = databaseRef.child('users').child('users').child(user.uid).child('credits');
        final snapshot = await creditsRef.get();
        int currentCredits = 0;
        if (snapshot.exists && snapshot.value != null) {
          if (snapshot.value is int) {
            currentCredits = snapshot.value as int;
          } else if (snapshot.value is String) {
            currentCredits = int.tryParse(snapshot.value as String) ?? 0;
          }
        }
        int newCredits = currentCredits - 20;
        if (newCredits < 0) newCredits = 0;
        await creditsRef.set(newCredits);
        if (mounted) {
          setState(() { _userCredits = newCredits; });
        }
      }
    } catch (e) {
      // ignore subtract error
    }
    return true;
  }

  // Inizializza listener live dei crediti utente
  void _initializeCreditsStream() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final ref = FirebaseDatabase.instance.ref().child('users').child('users').child(user.uid).child('credits');
      _creditsSubscription?.cancel();
      _creditsSubscription = ref.onValue.listen((event) {
        int newCredits = 0;
        final val = event.snapshot.value;
        if (val is int) {
          newCredits = val;
        } else if (val is String) {
          newCredits = int.tryParse(val) ?? 0;
        }
        if (mounted) {
          setState(() {
            _userCredits = newCredits;
            // Non mostrare automaticamente lo snackbar; verrà mostrato solo su tap input/invio/suggested
          });
        }
      });
    } catch (_) {}
  }
  Future<void> _loadStatsData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Ottieni user e videoId
      final user = FirebaseAuth.instance.currentUser;
      final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
      
      // Prima carica le piattaforme selezionate dal database Firebase
      print('[STATS] Caricamento piattaforme selezionate...');
      await _loadPlatformsFromFirebase();
      
      // Carica i dati salvati dal database Firebase
      if (user != null && videoId != null) {
        final videoOwnerId = widget.video['user_id']?.toString() ?? user.uid;
        print('[STATS] Caricamento dati API salvati...');
        final savedStats = await _statsService.loadApiStatsFromFirebase(
          userId: videoOwnerId,
          videoId: videoId,
        );
        
        // Popola i dati salvati nelle strutture esistenti
        savedStats.forEach((key, stats) {
          final platform = stats['platform'] as String;
          final accountId = stats['account_id'] as String;
          
          // Trova l'accountKey corrispondente
          String? accountKey;
          _accountMeta.forEach((k, meta) {
            if (meta['platform'] == platform && meta['account_id'] == accountId) {
              accountKey = k;
            }
          });
          
          if (accountKey != null) {
            _statsData['likes']![accountKey!] = (stats['likes'] ?? 0).toDouble();
            _statsData['views']![accountKey!] = (stats['views'] ?? 0).toDouble();
            _statsData['comments']![accountKey!] = (stats['comments'] ?? 0).toDouble();
            print('[STATS] Dati caricati per $accountKey: likes=${stats['likes']}, views=${stats['views']}, comments=${stats['comments']}');
          }
        });
      }
      
      // Ottieni le piattaforme selezionate
      final selectedPlatforms = _getSelectedPlatforms();
      print('[STATS] Piattaforme selezionate: $selectedPlatforms');
      
      // Otteniamo gli ID per ogni piattaforma dal video
      final String tikTokId = widget.video['tiktok_id']?.toString() ?? '';
      final String youtubeId = widget.video['youtube_id']?.toString() ?? '';
      final String instagramId = widget.video['instagram_id']?.toString() ?? '';
      final String threadsId = widget.video['threads_id']?.toString() ?? '';
      final String facebookId = widget.video['facebook_id']?.toString() ?? '';
      final String twitterId = widget.video['twitter_id']?.toString() ?? '';
      final db = FirebaseDatabase.instance.ref();

      // --- Carica manual_views per Instagram, Facebook, Threads ---
      for (final platform in ['Instagram', 'Facebook', 'Threads']) {
        if (user != null && videoId != null) {
            final accountsSnap = await db.child('users').child('users').child(user.uid).child('videos').child(videoId).child('accounts').child(platform).get();
            if (accountsSnap.exists) {
              final accounts = accountsSnap.value;
              if (accounts is Map) {
                for (final entry in accounts.entries) {
                  final key = entry.key.toString();
                  final acc = entry.value;
                  if (acc is Map) {
                    final accUser = (acc['account_username'] ?? acc['username'] ?? '').toString().trim().toLowerCase();
                    final accDisplay = (acc['account_display_name'] ?? acc['display_name'] ?? '').toString().trim().toLowerCase();
                    final manualViews = acc['manual_views'];
                    final manualLikes = acc['manual_likes'];
                    final manualComments = acc['manual_comments'];
                    // Trova l'accountKey corrispondente
                    String? foundAccountKey;
                    _accountMeta.forEach((k, meta) {
                      final metaUser = (meta['account_username'] ?? meta['username'] ?? '').toString().trim().toLowerCase();
                      final metaDisplay = (meta['account_display_name'] ?? meta['display_name'] ?? '').toString().trim().toLowerCase();
                      if ((metaUser.isNotEmpty && metaUser == accUser) ||
                          (metaDisplay.isNotEmpty && metaDisplay == accDisplay)) {
                        foundAccountKey = k;
                      }
                    });
                    if (foundAccountKey != null) {
                      if (manualViews != null) _manualViews[foundAccountKey!] = int.tryParse(manualViews.toString()) ?? 0;
                      if (manualLikes != null) _manualLikes[foundAccountKey!] = int.tryParse(manualLikes.toString()) ?? 0;
                      if (manualComments != null) _manualComments[foundAccountKey!] = int.tryParse(manualComments.toString()) ?? 0;
                    }
                  }
                }
              } else if (accounts is List) {
                for (int i = 0; i < accounts.length; i++) {
                  final acc = accounts[i];
                  if (acc is Map) {
                    final accUser = (acc['account_username'] ?? acc['username'] ?? '').toString().trim().toLowerCase();
                    final accDisplay = (acc['account_display_name'] ?? acc['display_name'] ?? '').toString().trim().toLowerCase();
                    final manualViews = acc['manual_views'];
                    final manualLikes = acc['manual_likes'];
                    final manualComments = acc['manual_comments'];
                    String? foundAccountKey;
                    _accountMeta.forEach((k, meta) {
                      final metaUser = (meta['account_username'] ?? meta['username'] ?? '').toString().trim().toLowerCase();
                      final metaDisplay = (meta['account_display_name'] ?? meta['display_name'] ?? '').toString().trim().toLowerCase();
                      if ((metaUser.isNotEmpty && metaUser == accUser) ||
                          (metaDisplay.isNotEmpty && metaDisplay == accDisplay)) {
                        foundAccountKey = k;
                      }
                    });
                    if (foundAccountKey != null) {
                      if (manualViews != null) _manualViews[foundAccountKey!] = int.tryParse(manualViews.toString()) ?? 0;
                      if (manualLikes != null) _manualLikes[foundAccountKey!] = int.tryParse(manualLikes.toString()) ?? 0;
                      if (manualComments != null) _manualComments[foundAccountKey!] = int.tryParse(manualComments.toString()) ?? 0;
                  }
                }
              }
            }
          }
        }
      }
      
      // Verifica se ci sono date di pubblicazione nei dati Firebase
      if (widget.video['timestamp'] != null && widget.video['publish_date'] == null) {
        // Converti il timestamp in data leggibile
        try {
          final timestamp = widget.video['timestamp'] as int;
          final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
          widget.video['publish_date'] = DateFormat('yyyy-MM-dd HH:mm').format(date);
        } catch (e) {
          print('Error converting timestamp to date: $e');
        }
      }
      
      // Mappa per tenere traccia degli errori per piattaforma
      Map<String, String> errors = {};

      // Carica i dati per TikTok (nuovo formato: accounts in sottocartelle)
      try {
        final user = FirebaseAuth.instance.currentUser;
        final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
        final videoOwnerId = widget.video['user_id']?.toString() ?? user?.uid;
        if (videoOwnerId != null && videoId != null) {
          final databaseRef = FirebaseDatabase.instance.ref();
          final tkAccountsSnap = await databaseRef.child('users').child('users').child(videoOwnerId).child('videos').child(videoId).child('accounts').child('TikTok').get();
          if (tkAccountsSnap.exists) {
            final raw = tkAccountsSnap.value;
            List<dynamic> tkAccounts;
            if (raw is List) {
              tkAccounts = raw;
            } else if (raw is Map) {
              tkAccounts = raw.values.toList();
            } else {
              tkAccounts = [];
            }
            int tkIdx = 1;
            for (final account in tkAccounts) {
              if (account is Map<dynamic, dynamic>) {
                final mediaId = account['media_id']?.toString() ?? '';
                final profileImageUrl = (account['account_profile_image_url'] ?? account['profile_image_url'] ?? '').toString();
                final username = (account['account_username'] ?? account['username'] ?? '').toString();
                final displayName = (account['account_display_name'] ?? account['display_name'] ?? username).toString();
                final tkId = (account['account_id'] ?? account['id'] ?? '').toString();
                final accountKey = 'tiktok'+tkIdx.toString();
                _accountMeta[accountKey] = {
                  'profile_image_url': profileImageUrl,
                  'display_name': displayName,
                  'username': username,
                  'account_username': username,
                  'account_display_name': displayName,
                  'platform': 'tiktok',
                  'account_id': tkId,
                };
                // Default a 0, aggiorno dopo eventuale chiamata API
                _statsData['likes']![accountKey] = 0;
                _statsData['views']![accountKey] = 0;
                _statsData['comments']![accountKey] = 0;
                // Se disponibile mediaId (o tikTokId a livello video), prova a caricare le metriche
                final effectiveId = mediaId.isNotEmpty ? mediaId : tikTokId;
                if (effectiveId.isNotEmpty) {
                  try {
                    final tiktokStats = await _statsService.getTikTokStats(effectiveId);
                    _statsData['likes']![accountKey] = (tiktokStats['likes'] ?? 0).toDouble();
                    _statsData['views']![accountKey] = (tiktokStats['views'] ?? 0).toDouble();
                    _statsData['comments']![accountKey] = (tiktokStats['comments'] ?? 0).toDouble();
                    // Salva i dati nel database Firebase
                    final ownerId = widget.video['user_id']?.toString() ?? user?.uid ?? '';
                    await _statsService.saveApiStatsToFirebase(
                      userId: ownerId,
                      videoId: videoId,
                      platform: 'tiktok',
                      accountId: tkId.isNotEmpty ? tkId : 'main',
                      stats: tiktokStats,
                      accountUsername: username.isNotEmpty ? username : 'tiktok_user',
                      accountDisplayName: displayName.isNotEmpty ? displayName : 'TikTok Account',
                    );
                    // Aggiorna i totali dell'utente
                    await _statsService.updateUserTotals(
                      userId: ownerId,
                      platform: 'tiktok',
                      accountId: tkId.isNotEmpty ? tkId : 'main',
                      newStats: tiktokStats,
                      accountUsername: username.isNotEmpty ? username : 'tiktok_user',
                      accountDisplayName: displayName.isNotEmpty ? displayName : 'TikTok Account',
                    );
                  } catch (_) {}
                }
                tkIdx++;
              }
            }
            setState(() {});
          } else {
            // Fallback: usa l'ID video a livello globale come singolo account aggregato
            if (tikTokId.isNotEmpty) {
              try {
                final tiktokStats = await _statsService.getTikTokStats(tikTokId);
                _statsData['likes']!['tiktok'] = (tiktokStats['likes'] ?? 0).toDouble();
                _statsData['views']!['tiktok'] = (tiktokStats['views'] ?? 0).toDouble();
                _statsData['comments']!['tiktok'] = (tiktokStats['comments'] ?? 0).toDouble();
                final ownerId = widget.video['user_id']?.toString() ?? user?.uid ?? '';
                await _statsService.saveApiStatsToFirebase(
                  userId: ownerId,
                  videoId: videoId,
                  platform: 'tiktok',
                  accountId: 'main',
                  stats: tiktokStats,
                  accountUsername: 'tiktok_user',
                  accountDisplayName: 'TikTok Account',
                );
                await _statsService.updateUserTotals(
                  userId: ownerId,
                  platform: 'tiktok',
                  accountId: 'main',
                  newStats: tiktokStats,
                  accountUsername: 'tiktok_user',
                  accountDisplayName: 'TikTok Account',
                );
              } catch (e) {
                errors['tiktok'] = e.toString();
                _statsData['likes']!['tiktok'] = 0;
                _statsData['views']!['tiktok'] = 0;
                _statsData['comments']!['tiktok'] = 0;
              }
            } else {
              _statsData['likes']!['tiktok'] = 0;
              _statsData['views']!['tiktok'] = 0;
              _statsData['comments']!['tiktok'] = 0;
            }
          }
        } else {
          _statsData['likes']!['tiktok'] = 0;
          _statsData['views']!['tiktok'] = 0;
          _statsData['comments']!['tiktok'] = 0;
        }
      } catch (e) {
        errors['tiktok'] = e.toString();
      }

      // Carica i dati per YouTube (multi-account, Google Sign-In silenzioso per ogni account)
      try {
        final user = FirebaseAuth.instance.currentUser;
        final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
        final ownerId = widget.video['user_id']?.toString() ?? user?.uid;
        if (ownerId != null && videoId != null) {
          final databaseRef = FirebaseDatabase.instance.ref();
            final ytAccountsSnap = await databaseRef.child('users').child('users').child(ownerId).child('videos').child(videoId).child('accounts').child('YouTube').get();
            if (ytAccountsSnap.exists) {
              final raw = ytAccountsSnap.value;
              List<dynamic> ytAccounts;
              if (raw is List) {
                ytAccounts = raw;
              } else if (raw is Map) {
                ytAccounts = raw.values.toList();
              } else {
                ytAccounts = [];
              }
              int ytIdx = 1;
              for (final account in ytAccounts) {
                
                if (account is Map<dynamic, dynamic>) {
                  final videoIdYt = account['youtube_video_id']?.toString() ?? '';
                  final profileImageUrl = (account['account_profile_image_url'] ?? account['profile_image_url'] ?? '').toString();
                  final username = (account['account_username'] ?? account['username'] ?? '').toString();
                  final displayName = (account['account_display_name'] ?? account['display_name'] ?? username).toString();
                  final ytId = (account['account_id'] ?? account['id'] ?? '').toString();
                  final accountKey = 'youtube'+ytIdx.toString();
                  _accountMeta[accountKey] = {
                    'profile_image_url': profileImageUrl,
                    'display_name': displayName,
                    'username': username,
                    'account_username': username,
                    'account_display_name': displayName,
                    'platform': 'youtube',
                    'account_id': ytId,
                  };
                  // Default a 0, aggiorno dopo la chiamata API
                  _statsData['likes']![accountKey] = 0;
                  _statsData['views']![accountKey] = 0;
                  _statsData['comments']![accountKey] = 0;
                  // Effettua Google Sign-In silenzioso e chiama API per ogni account
                  if (videoIdYt.isNotEmpty) {
                    try {
                      
                      try {
                        final youtubeStats = await _statsService.getYouTubeStats(videoIdYt, null); // null -> forza sign-in silenzioso
                        _statsData['likes']![accountKey] = (youtubeStats['likes'] ?? 0).toDouble();
                        _statsData['views']![accountKey] = (youtubeStats['views'] ?? 0).toDouble();
                        _statsData['comments']![accountKey] = (youtubeStats['comments'] ?? 0).toDouble();
                        
                        
                        // Salva i dati nel database Firebase
                        final currentUser = FirebaseAuth.instance.currentUser;
                        final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
                        final ownerId = widget.video['user_id']?.toString() ?? currentUser?.uid ?? '';
                        if (videoId != null) {
                          await _statsService.saveApiStatsToFirebase(
                            userId: ownerId,
                            videoId: videoId,
                            platform: 'youtube',
                            accountId: ytId,
                            stats: youtubeStats,
                            accountUsername: username,
                            accountDisplayName: displayName,
                          );
                          
                          // Aggiorna i totali dell'utente
                          await _statsService.updateUserTotals(
                            userId: ownerId,
                            platform: 'youtube',
                            accountId: ytId,
                            newStats: youtubeStats,
                            accountUsername: username,
                            accountDisplayName: displayName,
                          );
                        }
                      } catch (apiErr) {}
                    } catch (e) {}
                  } else {
                    (_accountMeta[accountKey] ??= {})['missing_token'] = true;
                  }
                  ytIdx++;
                }
              }
              setState(() {}); // Forza aggiornamento UI dopo caricamento
          }
        }
      } catch (e) {
        print('Errore caricamento account YouTube da Firebase: $e');
      }
      
      print('[STATS] 🔍 Controllo YouTube - ID: $youtubeId, Piattaforme selezionate: $selectedPlatforms');
      print('[STATS] 🔍 YouTube incluso nelle piattaforme: ${selectedPlatforms.contains('youtube')}');
      
      if (youtubeId?.isNotEmpty == true && selectedPlatforms.contains('youtube')) {
        print('[STATS] ✅ Caricamento dati YouTube...');
        try {
          // Recupera access_token di YouTube dal database Firebase
          String? youtubeAccessToken;
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final databaseRef = FirebaseDatabase.instance.ref();
            final youtubeSnapshot = await databaseRef.child('users').child(user.uid).child('youtube').get();
            print('[YOUTUBE] Recupero dati YouTube per user: ${user.uid}');
            print('[YOUTUBE] YouTube ID del video: $youtubeId');
            print('[YOUTUBE] Percorso database: users/${user.uid}/youtube');
            
            if (youtubeSnapshot.exists) {
              final youtubeData = youtubeSnapshot.value as Map<dynamic, dynamic>;
              print('[YOUTUBE] Account YouTube trovati: ${youtubeData.keys}');
              print('[YOUTUBE] Dati completi YouTube: $youtubeData');
              
              // Cerca l'account che ha user_id corrispondente oppure prendi il primo valido
              Map<dynamic, dynamic>? accountData;
              String? accountId;
              
              for (final entry in youtubeData.entries) {
                final acc = entry.value as Map<dynamic, dynamic>;
                final userId = acc['user_id']?.toString() ?? 'N/A';
                final hasAccessToken = acc['access_token'] != null && acc['access_token'].toString().isNotEmpty;
                final accessTokenPreview = hasAccessToken ? '${acc['access_token'].toString().substring(0, 10)}...' : 'N/A';
                
                print('[YOUTUBE] Controllo account ${entry.key}:');
                print('[YOUTUBE]   - user_id: $userId');
                print('[YOUTUBE]   - access_token presente: $hasAccessToken');
                print('[YOUTUBE]   - access_token preview: $accessTokenPreview');
                print('[YOUTUBE]   - dati completi account: $acc');
                
                if (userId == youtubeId && hasAccessToken) {
                  accountData = acc;
                  accountId = entry.key.toString();
                  print('[YOUTUBE] ✅ Account trovato con user_id corrispondente: $accountId');
                  break;
                }
              }
              
              // Se non trovato, prendi il primo con access_token valido
              if (accountData == null) {
                print('[YOUTUBE] Nessun account con user_id corrispondente, cerco il primo con token valido...');
                for (final entry in youtubeData.entries) {
                  final acc = entry.value as Map<dynamic, dynamic>;
                  final hasAccessToken = acc['access_token'] != null && acc['access_token'].toString().isNotEmpty;
                  
                  if (hasAccessToken) {
                    accountData = acc;
                    accountId = entry.key.toString();
                    print('[YOUTUBE] ✅ Usando primo account con token valido: $accountId');
                    break;
                  }
                }
              }
              
              if (accountData != null && accountData['access_token'] != null && accountData['access_token'].toString().isNotEmpty) {
                youtubeAccessToken = accountData['access_token'].toString();
                print('[YOUTUBE] ✅ Token recuperato per account $accountId');
                print('[YOUTUBE] ✅ Token preview: ${youtubeAccessToken.substring(0, 10)}...');
                print('[YOUTUBE] ✅ Token completo: $youtubeAccessToken');
                print('[YOUTUBE] ✅ Lunghezza token: ${youtubeAccessToken.length} caratteri');
              } else {
                print('[YOUTUBE] ❌ Nessun access_token trovato nel database');
                print('[YOUTUBE] ❌ Account data: $accountData');
                print('[YOUTUBE] 🔄 Userò Google Sign-In come fallback');
              }
            } else {
              print('[YOUTUBE] ❌ Nessun account YouTube trovato nel database');
              print('[YOUTUBE] 🔄 Userò Google Sign-In come fallback');
            }
          } else {
            print('[YOUTUBE] ❌ Utente non autenticato');
            print('[YOUTUBE] 🔄 Userò Google Sign-In come fallback');
          }
          
          final youtubeStats = await _statsService.getYouTubeStats(youtubeId!, youtubeAccessToken);
          _statsData['likes']!['youtube'] = (youtubeStats['likes'] ?? 0).toDouble();
          _statsData['views']!['youtube'] = (youtubeStats['views'] ?? 0).toDouble();
          _statsData['comments']!['youtube'] = (youtubeStats['comments'] ?? 0).toDouble();
          
          print('[YOUTUBE] Statistiche recuperate: likes=${youtubeStats['likes']}, views=${youtubeStats['views']}, comments=${youtubeStats['comments']}');
        } catch (e) {
          errors['youtube'] = e.toString();
          print('[YOUTUBE] ERRORE: $e');
          // Non inserisco valori di esempio, lascio a 0
        }
      } else {
        if (youtubeId?.isEmpty != false) {
          print('[STATS] ⚠️ YouTube ID vuoto');
        }
        if (!selectedPlatforms.contains('youtube')) {
          print('[STATS] ⚠️ YouTube non incluso nelle piattaforme selezionate');
        }
        // Non inserisco valori di esempio, lascio a 0
      }
      // Carica i dati per Instagram (multi-account, SEMPRE da Firebase, come Facebook)
      try {
        final user = FirebaseAuth.instance.currentUser;
        final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
        if (user != null && videoId != null) {
          final databaseRef = FirebaseDatabase.instance.ref();
            final igAccountsSnap = await databaseRef.child('users').child('users').child(user.uid).child('videos').child(videoId).child('accounts').child('Instagram').get();
            if (igAccountsSnap.exists) {
              final raw = igAccountsSnap.value;
              List<dynamic> igAccounts;
              if (raw is List) {
                igAccounts = raw;
              } else if (raw is Map) {
                igAccounts = raw.values.toList();
              } else {
                igAccounts = [];
              }
              int igIdx = 1;
              for (final account in igAccounts) {
                if (account is Map<dynamic, dynamic>) {
                  final mediaId = account['media_id']?.toString() ?? '';
                  final profileImageUrl = (account['account_profile_image_url'] ?? account['profile_image_url'] ?? '').toString();
                  final username = (account['account_username'] ?? account['username'] ?? '').toString();
                  final displayName = (account['account_display_name'] ?? account['display_name'] ?? username).toString();
                  final igId = (account['account_id'] ?? account['id'] ?? '').toString();
                  final accountKey = 'instagram'+igIdx.toString();
                  _accountMeta[accountKey] = {
                    'profile_image_url': profileImageUrl,
                    'display_name': displayName,
                    'username': username,
                    'account_username': username,
                    'account_display_name': displayName,
                    'platform': 'instagram',
                    'account_id': igId,
                  };
                  // Default a 0, aggiorno dopo la chiamata API
                  _statsData['likes']![accountKey] = 0;
                  _statsData['views']![accountKey] = 0;
                  _statsData['comments']![accountKey] = 0;
                  // Recupera access_token per la pagina Instagram
                  if (mediaId.isNotEmpty && igId.isNotEmpty) {
                    try {
                      final tokenPath = 'users/${user.uid}/instagram/$igId/facebook_access_token';
                      final tokenSnap = await databaseRef.child('users').child(user.uid).child('instagram').child(igId).child('facebook_access_token').get();
                      if (tokenSnap.exists) {
                        final accessToken = tokenSnap.value.toString();
                        try {
                          final instagramStats = await _statsService.getInstagramStats(mediaId, accessToken);
                          _statsData['likes']![accountKey] = (instagramStats['likes'] ?? 0).toDouble();
                          _statsData['views']![accountKey] = (instagramStats['views'] ?? 0).toDouble();
                          _statsData['comments']![accountKey] = (instagramStats['comments'] ?? 0).toDouble();
                          
                          
                          // Salva i dati nel database Firebase
                          final currentUser = FirebaseAuth.instance.currentUser;
                          final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
                          final ownerId = widget.video['user_id']?.toString() ?? currentUser?.uid ?? '';
                          if (videoId != null) {
                            await _statsService.saveApiStatsToFirebase(
                              userId: ownerId,
                              videoId: videoId,
                              platform: 'instagram',
                              accountId: igId,
                              stats: instagramStats,
                              accountUsername: username,
                              accountDisplayName: displayName,
                            );
                            
                            // Aggiorna i totali dell'utente
                            await _statsService.updateUserTotals(
                              userId: ownerId,
                              platform: 'instagram',
                              accountId: igId,
                              newStats: instagramStats,
                              accountUsername: username,
                              accountDisplayName: displayName,
                            );
                          }
                        } catch (apiErr) {}
                      } else {
                        (_accountMeta[accountKey] ??= {})['missing_token'] = true;
                      }
                    } catch (e) {
                      
                    }
                  } else {
                    (_accountMeta[accountKey] ??= {})['missing_token'] = true;
                  }
                  igIdx++;
                }
              }
              setState(() {}); // Forza aggiornamento UI dopo caricamento
          }
        }
      } catch (e) {
        print('Errore caricamento account Instagram da Firebase: $e');
      }

      // Carica i dati per Threads (multi-account, SEMPRE da Firebase, come Instagram e Facebook)
        try {
          final user = FirebaseAuth.instance.currentUser;
          final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
        
        if (user != null && videoId != null) {
              final databaseRef = FirebaseDatabase.instance.ref();
            final threadsAccountsSnap = await databaseRef.child('users').child('users').child(user.uid).child('videos').child(videoId).child('accounts').child('Threads').get();
            if (threadsAccountsSnap.exists) {
              final raw = threadsAccountsSnap.value;
              List<dynamic> threadsAccounts;
              if (raw is List) {
                threadsAccounts = raw;
              } else if (raw is Map) {
                threadsAccounts = raw.values.toList();
              } else {
                threadsAccounts = [];
              }
              int thIdx = 1;
              for (final account in threadsAccounts) {
                if (account is Map<dynamic, dynamic>) {
                  final postId = account['post_id']?.toString() ?? '';
                  final profileImageUrl = (account['account_profile_image_url'] ?? account['profile_image_url'] ?? '').toString();
                  final username = (account['account_username'] ?? account['username'] ?? '').toString();
                  final displayName = (account['account_display_name'] ?? account['display_name'] ?? username).toString();
                  final thId = (account['account_id'] ?? account['id'] ?? '').toString();
                  final accountKey = 'threads'+thIdx.toString();
                  _accountMeta[accountKey] = {
                    'profile_image_url': profileImageUrl,
                    'display_name': displayName,
                    'username': username,
                    'account_username': username,
                    'account_display_name': displayName,
                    'platform': 'threads',
                    'account_id': thId,
                  };
                  // Default a 0, aggiorno dopo la chiamata API
                  _statsData['likes']![accountKey] = 0;
                  _statsData['views']![accountKey] = 0;
                  _statsData['comments']![accountKey] = 0;
                  // Recupera access_token per l'account Threads
                  if (postId.isNotEmpty && thId.isNotEmpty) {
                    try {
                      final tokenPath = 'users/users/${user.uid}/social_accounts/threads/$thId/access_token';
                      final tokenSnap = await databaseRef.child('users').child('users').child(user.uid).child('social_accounts').child('threads').child(thId).child('access_token').get();
                      if (tokenSnap.exists) {
                        final accessToken = tokenSnap.value.toString();
                        try {
                          final threadsStats = await _statsService.getThreadsStats(postId, accessToken);
                          _statsData['likes']![accountKey] = (threadsStats['likes'] ?? 0).toDouble();
                          _statsData['views']![accountKey] = (threadsStats['views'] ?? 0).toDouble();
                          _statsData['comments']![accountKey] = (threadsStats['comments'] ?? 0).toDouble();
                          
                          
                          // Salva i dati nel database Firebase
                          final currentUser = FirebaseAuth.instance.currentUser;
                          final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
                          final ownerId = widget.video['user_id']?.toString() ?? currentUser?.uid ?? '';
                          if (videoId != null) {
                            await _statsService.saveApiStatsToFirebase(
                              userId: ownerId,
                              videoId: videoId,
                              platform: 'threads',
                              accountId: thId,
                              stats: threadsStats,
                              accountUsername: username,
                              accountDisplayName: displayName,
                            );
                            
                            // Aggiorna i totali dell'utente
                            await _statsService.updateUserTotals(
                              userId: ownerId,
                              platform: 'threads',
                              accountId: thId,
                              newStats: threadsStats,
                              accountUsername: username,
                              accountDisplayName: displayName,
                            );
                          }
                        } catch (apiErr) {}
                      } else {
                        (_accountMeta[accountKey] ??= {})['missing_token'] = true;
                      }
                    } catch (e) {
                      
                    }
                  } else {
                    (_accountMeta[accountKey] ??= {})['missing_token'] = true;
                  }
                  thIdx++;
                }
              }
              setState(() {}); // Forza aggiornamento UI dopo caricamento
          }
        }
      } catch (e) {
        print('Errore caricamento account Threads da Firebase: $e');
      }

      // Carica i dati per Facebook (multi-account, SEMPRE da Firebase)
        try {
          final user = FirebaseAuth.instance.currentUser;
          final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
        
        if (user != null && videoId != null) {
              final databaseRef = FirebaseDatabase.instance.ref();
          final fbAccountsSnap = await databaseRef.child('users').child('users').child(user.uid).child('videos').child(videoId).child('accounts').child('Facebook').get();
          if (fbAccountsSnap.exists) {
            final raw = fbAccountsSnap.value;
            List<dynamic> fbAccounts;
            if (raw is List) {
              fbAccounts = raw;
            } else if (raw is Map) {
              fbAccounts = raw.values.toList();
            } else {
              fbAccounts = [];
            }
            int fbIdx = 1;
            for (final account in fbAccounts) {
              if (account is Map<dynamic, dynamic>) {
                final postId = account['post_id']?.toString() ?? '';
                final profileImageUrl = (account['account_profile_image_url'] ?? account['profile_image_url'] ?? '').toString();
                final displayName = (account['account_display_name'] ?? account['display_name'] ?? '').toString();
                final pageId = (account['account_id'] ?? account['id'] ?? '').toString();
                final accountKey = 'facebook'+fbIdx.toString();
                _accountMeta[accountKey] = {
                  'profile_image_url': profileImageUrl,
                  'display_name': displayName,
                  'account_display_name': displayName,
                  'platform': 'facebook',
                  'account_id': pageId,
                };
                // Default a 0, aggiorno dopo la chiamata API
                _statsData['likes']![accountKey] = 0;
                _statsData['views']![accountKey] = 0;
                _statsData['comments']![accountKey] = 0;
                // Recupera access_token per la page
                if (postId.isNotEmpty && pageId.isNotEmpty) {
                  try {
                    final tokenPath = 'users/${user.uid}/facebook/$pageId/access_token';
                    final tokenSnap = await databaseRef.child('users').child(user.uid).child('facebook').child(pageId).child('access_token').get();
                    if (tokenSnap.exists) {
                      final accessToken = tokenSnap.value.toString();
                      try {
                        final facebookStats = await _statsService.getFacebookStats(postId, accessToken);
                        _statsData['likes']![accountKey] = (facebookStats['likes'] ?? 0).toDouble();
                        _statsData['views']![accountKey] = (facebookStats['views'] ?? 0).toDouble();
                        _statsData['comments']![accountKey] = (facebookStats['comments'] ?? 0).toDouble();
                        
                        
                        // Salva i dati nel database Firebase
                        final currentUser = FirebaseAuth.instance.currentUser;
                        final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
                        final ownerId = widget.video['user_id']?.toString() ?? currentUser?.uid ?? '';
                        if (videoId != null) {
                          await _statsService.saveApiStatsToFirebase(
                            userId: ownerId,
                            videoId: videoId,
                            platform: 'facebook',
                            accountId: pageId,
                            stats: facebookStats,
                            accountUsername: displayName,
                            accountDisplayName: displayName,
                          );
                          
                          // Aggiorna i totali dell'utente
                          await _statsService.updateUserTotals(
                            userId: ownerId,
                            platform: 'facebook',
                            accountId: pageId,
                            newStats: facebookStats,
                            accountUsername: displayName,
                            accountDisplayName: displayName,
                          );
                        }
                      } catch (apiErr) {}
                    } else {
                      // Mostra un messaggio visibile in UI (es. tooltip o print)
                      (_accountMeta[accountKey] ??= {})['missing_token'] = true;
          }
        } catch (e) {
                    
                  }
                } else {
                  (_accountMeta[accountKey] ??= {})['missing_token'] = true;
                }
                fbIdx++;
              }
            }
            setState(() {}); // Forza aggiornamento UI dopo caricamento
          }
        }
      } catch (e) {
        print('Errore caricamento account Facebook da Firebase: $e');
      }
      // Carica i dati per Twitter
      try {
        final user = FirebaseAuth.instance.currentUser;
        final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString() ?? '';
        if (user != null && videoId.isNotEmpty) {
          final databaseRef = FirebaseDatabase.instance.ref();
        final twitterAccountsSnapshot = await databaseRef.child('users').child('users').child(user.uid).child('videos').child(videoId).child('accounts').child('Twitter').get();
        if (twitterAccountsSnapshot.exists) {
          final raw = twitterAccountsSnapshot.value;
          List<dynamic> twitterAccounts;
          if (raw is List) {
            twitterAccounts = raw;
          } else if (raw is Map) {
            twitterAccounts = raw.values.toList();
          } else {
            twitterAccounts = [];
          }
          if (twitterAccounts.isNotEmpty) {
            final firstAccount = twitterAccounts[0] as Map<dynamic, dynamic>;
            final twitterProfileId = (firstAccount['account_id'] ?? firstAccount['id'] ?? '').toString();
            final twitterPostId = firstAccount['post_id']?.toString();
            final username = (firstAccount['account_username'] ?? firstAccount['username'] ?? '').toString();
            final displayName = (firstAccount['account_display_name'] ?? firstAccount['display_name'] ?? username).toString();
            final profileImageUrl = (firstAccount['account_profile_image_url'] ?? firstAccount['profile_image_url'] ?? '').toString();
            final accountKey = 'twitter1';
            _accountMeta[accountKey] = {
              'profile_image_url': profileImageUrl,
              'display_name': displayName,
              'username': username,
              'account_username': username,
              'account_display_name': displayName,
              'platform': 'twitter',
              'account_id': twitterProfileId,
            };
            _statsData['likes']![accountKey] = 0;
            _statsData['views']![accountKey] = 0;
            _statsData['comments']![accountKey] = 0;
            if (twitterProfileId != null && twitterProfileId.isNotEmpty && twitterPostId != null && twitterPostId.isNotEmpty) {
              final ownerId = widget.video['user_id']?.toString() ?? user.uid;
              final twitterStats = await _statsService.getTwitterStats(userId: ownerId, videoId: videoId);
              _statsData['likes']![accountKey] = (twitterStats['likes'] ?? 0).toDouble();
              _statsData['views']![accountKey] = (twitterStats['views'] ?? 0).toDouble();
              _statsData['comments']![accountKey] = (twitterStats['comments'] ?? 0).toDouble();
              await _statsService.saveApiStatsToFirebase(
                userId: ownerId,
                videoId: videoId,
                platform: 'twitter',
                accountId: twitterProfileId,
                stats: twitterStats,
                accountUsername: username.isNotEmpty ? username : 'twitter_user',
                accountDisplayName: displayName.isNotEmpty ? displayName : 'Twitter Account',
              );
              await _statsService.updateUserTotals(
                userId: ownerId,
                platform: 'twitter',
                accountId: twitterProfileId,
                newStats: twitterStats,
                accountUsername: username.isNotEmpty ? username : 'twitter_user',
                accountDisplayName: displayName.isNotEmpty ? displayName : 'Twitter Account',
              );
            } else {
              errors['twitter'] = 'Twitter profile ID or post ID missing';
            }
          } else {
            errors['twitter'] = 'No Twitter account linked to this video';
          }
        } else {
          errors['twitter'] = 'No Twitter account info found for this video';
      }
    } else {
      errors['twitter'] = 'User not authenticated or videoId missing';
      _statsData['likes']!['twitter'] = 0;
      _statsData['views']!['twitter'] = 0;
      _statsData['comments']!['twitter'] = 0;
    }
      } catch (e) {
        errors['twitter'] = e.toString();
        _statsData['likes']!['twitter'] = 0;
        _statsData['views']!['twitter'] = 0;
        _statsData['comments']!['twitter'] = 0;
      }

      setState(() {
        // Solo aggiorna la UI, NON riassegnare _statsData
        // Se ci sono errori, mostra un messaggio riassuntivo
        if (errors.isNotEmpty) {
          List<String> errorMessages = [];
          errors.forEach((platform, error) {
            errorMessages.add('$platform: ${error.split(':').first}');
          });
          _errorMessage = 'Alcuni dati potrebbero non essere aggiornati: ${errorMessages.join(', ')}';
        }
      });
      // --- AGGIUNTA: salva i totali aggregati in Firebase ---
      await _saveAggregatedStatsToFirebase();
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore generale nel caricamento dei dati: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tabController.dispose();
    _chatController.dispose();
    _chatFocusNode.dispose();
    // Rimuovi i listener prima di eliminare i controller
    try {
      _chatScrollController.removeListener(_onChatScroll);
    } catch (_) {}
    try {
      _sheetScrollController?.removeListener(_onSheetScroll);
    } catch (_) {}
    _chatScrollController.dispose();
    try { _creditsSubscription?.cancel(); } catch (_) {}
    _chatMessagesStream = null; // Pulisci lo stream
    _feedbackTimer?.cancel(); // Cancella il timer del feedback
    super.dispose();
  }

  // Refresh data for all selected platforms
  Future<void> _refreshData() async {
    print('[REFRESH] Starting refresh for all selected platforms...');
    
    // Reset error message
    setState(() {
      _errorMessage = null;
    });
    
    // Reload all stats data
    await _loadStatsData();
    
    // --- AGGIUNTA: salva i totali aggregati in Firebase anche dopo refresh ---
    await _saveAggregatedStatsToFirebase();
    
    if (_errorMessage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Statistics updated for all platforms'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // Mostra solo errori diversi da "Alcuni dati potrebbero non essere aggiornati"
      if (!_errorMessage!.startsWith('Alcuni dati potrebbero non essere aggiornati')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    

    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: null,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
          children: [
            const SizedBox(height: 64),
            
            
            // Loading indicator
            if (_isLoading)
              LinearProgressIndicator(
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              ),
              
            // Error message
            if (_errorMessage != null && !_errorMessage!.startsWith('Alcuni dati potrebbero non essere aggiornati'))
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.red[700]),
                      onPressed: () {
                        setState(() {
                          _errorMessage = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
              
            // Custom tab bar (same style as history_page.dart with All / Published / Draft)
            Visibility(visible: false, maintainState: true, child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.15)
                      : Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(30),
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
                    child: Padding(
                  padding: const EdgeInsets.all(3),
              child: TabBar(
                controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: theme.unselectedWidgetColor,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: const LinearGradient(
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
                          color: const Color(0xFF667eea).withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.transparent,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 12,
                      color: Colors.transparent,
                    ),
                    labelPadding: EdgeInsets.zero,
                    padding: EdgeInsets.zero,
                    tabs: [
                      Tab(
                        icon: AnimatedBuilder(
                          animation: _tabController,
                          builder: (context, child) {
                            final isSelected = _tabController.index == 0;
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                isSelected
                                    ? const Icon(
                                        Icons.video_library,
                                        size: 16,
                                        color: Colors.white,
                                      )
                                    : ShaderMask(
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
                                        child: const Icon(
                                          Icons.video_library,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                const SizedBox(width: 4),
                                isSelected
                                    ? const Text('Likes', style: TextStyle(color: Colors.white))
                                    : ShaderMask(
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
                                        child: const Text('Likes', style: TextStyle(color: Colors.white)),
                                      ),
                              ],
                            );
                          },
                        ),
                      ),
                      Tab(
                        icon: AnimatedBuilder(
                          animation: _tabController,
                          builder: (context, child) {
                            final isSelected = _tabController.index == 1;
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                isSelected
                                    ? const Icon(
                                        Icons.public,
                                        size: 16,
                                        color: Colors.white,
                                      )
                                    : ShaderMask(
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
                                        child: const Icon(
                                          Icons.public,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                const SizedBox(width: 4),
                                isSelected
                                    ? const Text('Views', style: TextStyle(color: Colors.white))
                                    : ShaderMask(
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
                                        child: const Text('Views', style: TextStyle(color: Colors.white)),
                                      ),
                              ],
                            );
                          },
                        ),
                      ),
                      Tab(
                        icon: AnimatedBuilder(
                          animation: _tabController,
                          builder: (context, child) {
                            final isSelected = _tabController.index == 2;
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                isSelected
                                    ? const Icon(
                                        Icons.drafts,
                                        size: 16,
                                        color: Colors.white,
                                      )
                                    : ShaderMask(
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
                                        child: const Icon(
                                          Icons.drafts,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                const SizedBox(width: 4),
                                isSelected
                                    ? const Text('Comments', style: TextStyle(color: Colors.white))
                                    : ShaderMask(
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
                                        child: const Text('Comments', style: TextStyle(color: Colors.white)),
                                      ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
            ),
            ),
            
            // Main content with TabBar overlay and PageView underneath
            Expanded(
              child: Stack(
                children: [
                  // Allow content to scroll under the suspended selector
                  PageView(
                controller: _pageController,
                      physics: const BouncingScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                  _tabController.animateTo(index);
                },
                children: [
                  _buildStatsSection('likes'),
                  _buildStatsSection('views'),
                  _buildStatsSection('comments'),
                ],
              ),
                  Positioned(
                    top: 8,
                    left: 16,
                    right: 16,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.15)
                                : Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(30),
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
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: TabBar(
                              controller: _tabController,
                              labelColor: Colors.white,
                              unselectedLabelColor: theme.unselectedWidgetColor,
                              indicator: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                gradient: const LinearGradient(
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
                                    color: const Color(0xFF667eea).withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              dividerColor: Colors.transparent,
                              indicatorSize: TabBarIndicatorSize.tab,
                              labelStyle: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.transparent,
                              ),
                              unselectedLabelStyle: const TextStyle(
                                fontWeight: FontWeight.normal,
                                fontSize: 12,
                                color: Colors.transparent,
                              ),
                              labelPadding: EdgeInsets.zero,
                              padding: EdgeInsets.zero,
                              tabs: [
                                Tab(
                                  icon: AnimatedBuilder(
                                    animation: _tabController,
                                    builder: (context, child) {
                                      final isSelected = _tabController.index == 0;
                                      return Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          isSelected
                                              ? const Icon(
                                                  Icons.video_library,
                                                  size: 16,
                                                  color: Colors.white,
                                                )
                                              : ShaderMask(
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
                                                  child: const Icon(
                                                    Icons.video_library,
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                          const SizedBox(width: 4),
                                          isSelected
                                              ? const Text('Likes', style: TextStyle(color: Colors.white))
                                              : ShaderMask(
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
                                                  child: const Text('Likes', style: TextStyle(color: Colors.white)),
                                                ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                Tab(
                                  icon: AnimatedBuilder(
                                    animation: _tabController,
                                    builder: (context, child) {
                                      final isSelected = _tabController.index == 1;
                                      return Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          isSelected
                                              ? const Icon(
                                                  Icons.public,
                                                  size: 16,
                                                  color: Colors.white,
                                                )
                                              : ShaderMask(
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
                                                  child: const Icon(
                                                    Icons.public,
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                          const SizedBox(width: 4),
                                          isSelected
                                              ? const Text('Views', style: TextStyle(color: Colors.white))
                                              : ShaderMask(
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
                                                  child: const Text('Views', style: TextStyle(color: Colors.white)),
                                                ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                Tab(
                                  icon: AnimatedBuilder(
                                    animation: _tabController,
                                    builder: (context, child) {
                                      final isSelected = _tabController.index == 2;
                                      return Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          isSelected
                                              ? const Icon(
                                                  Icons.drafts,
                                                  size: 16,
                                                  color: Colors.white,
                                                )
                                              : ShaderMask(
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
                                                  child: const Icon(
                                                    Icons.drafts,
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                          const SizedBox(width: 4),
                                          isSelected
                                              ? const Text('Comments', style: TextStyle(color: Colors.white))
                                              : ShaderMask(
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
                                                  child: const Text('Comments', style: TextStyle(color: Colors.white)),
                                                ),
                                        ],
                                      );
                                    },
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
          ],
        ),
      ),
      // Floating header overlay like about_page.dart
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(child: _buildHeader(context)),
      ),
    ],
  ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                Color(0xFF764ba2), // Colore finale: viola al 100%
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              transform: GradientRotation(135 * 3.14159 / 180), // Gradiente lineare a 135 gradi
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667eea).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _isAnalyzing ? null : _analyzeWithAI,
            child: Text('Analyze with AI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isAnalyzing ? Colors.grey.withOpacity(0.5) : Colors.transparent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
      ),
      // Floating action button per riaprire l'ultima analisi
      floatingActionButton: _lastAnalysis != null ? FloatingActionButton(
        heroTag: 'video_stats_fab',
        onPressed: _showLastAnalysis,
        backgroundColor: Colors.white,
        shape: CircleBorder(),
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
            Icons.psychology,
            color: Colors.white,
          ),
        ),
        tooltip: 'Show AI Analysis',
      ) : null,
    );
  }
  // Add the new header widget based on about_page.dart
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
                  // Refresh button
                  IconButton(
                    icon: Icon(
                      Icons.refresh,
                      color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                      size: 22,
                    ),
                    onPressed: _refreshData,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Variabile per memorizzare l'ultima analisi
  String? _lastAnalysis;
  int? _lastAnalysisTimestampMinutes; // <-- aggiunta per timestamp analisi IA
  
  // Variabili per la chat con l'IA
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final List<ChatMessage> _chatMessages = [];
  bool _isChatLoading = false;
  
  // Variabili per i pulsanti delle risposte IA
  Map<int, bool> _aiMessageLikes = {};
  Map<int, bool> _aiMessageDislikes = {};
  ValueNotifier<int> _feedbackUpdateNotifier = ValueNotifier(0);
  
  // Stream per aggiornamenti in tempo reale dei messaggi della chat
  Stream<DatabaseEvent>? _chatMessagesStream;
  ScrollController _chatScrollController = ScrollController();
  // Controller della ScrollView del contenuto della tendina (DraggableScrollableSheet)
  ScrollController? _sheetScrollController;
  // StateSetter della tendina per aggiornamenti immediati
  StateSetter? _sheetStateSetter;
  
  bool _isAtBottom() {
    try {
      if (_chatScrollController.hasClients) {
        final max = _chatScrollController.position.maxScrollExtent;
        final current = _chatScrollController.position.pixels;
        if ((max - current).abs() < 24) return true;
      }
      if (_sheetScrollController != null && _sheetScrollController!.hasClients) {
        final max = _sheetScrollController!.position.maxScrollExtent;
        final current = _sheetScrollController!.position.pixels;
        if ((max - current).abs() < 24) return true;
      }
    } catch (_) {}
    return false;
  }
  
  // Listener per aggiornare la visibilità del bottone "Bottom"
  void _onChatScroll() {
    if (mounted) setState(() {});
  }
  
  void _onSheetScroll() {
    if (mounted) setState(() {});
  }
  
  // Variabili per il feedback interno alla tendina
  String? _feedbackMessage;
  bool _showFeedback = false;
  Timer? _feedbackTimer;
  
  // Variabili per l'immagine profilo utente
  String? _userProfileImageUrl;

  // Metodi per gestire i pulsanti delle risposte IA
  void _copyAIMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showFeedbackMessage('Message copied to clipboard!');
    
    // Forza il rebuild immediato del bottom sheet per mostrare il feedback
    _feedbackUpdateNotifier.value++;
  }
  
  void _toggleLike(int messageIndex) {
    setState(() {
      if (_aiMessageLikes[messageIndex] == true) {
        _aiMessageLikes[messageIndex] = false;
        _aiMessageDislikes[messageIndex] = false;
      } else {
        _aiMessageLikes[messageIndex] = true;
        _aiMessageDislikes[messageIndex] = false;
      }
    });
    
    // Forza il rebuild immediato del bottom sheet
    _feedbackUpdateNotifier.value++;
    
    // Mostra feedback interno alla tendina solo quando si attiva
    if (_aiMessageLikes[messageIndex] == true) {
      _showFeedbackMessage('Thank you for your feedback!');
    }
  }
  
  void _toggleDislike(int messageIndex) {
    setState(() {
      if (_aiMessageDislikes[messageIndex] == true) {
        _aiMessageDislikes[messageIndex] = false;
        _aiMessageLikes[messageIndex] = false;
      } else {
        _aiMessageDislikes[messageIndex] = true;
        _aiMessageLikes[messageIndex] = false;
      }
    });
    
    // Forza il rebuild immediato del bottom sheet
    _feedbackUpdateNotifier.value++;
    
    // Mostra feedback interno alla tendina solo quando si attiva
    if (_aiMessageDislikes[messageIndex] == true) {
      _showFeedbackMessage('Thank you for your feedback!');
    }
  }
  
  // Metodo per mostrare il feedback interno
  void _showFeedbackMessage(String message) {
    // Cancella eventuali timer precedenti
    _feedbackTimer?.cancel();
    
    setState(() {
      _feedbackMessage = message;
      _showFeedback = true;
    });
    
    // Forza l'aggiornamento del ValueListenableBuilder
    _feedbackUpdateNotifier.value++;
    
    // Nascondi il feedback dopo 2 secondi
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showFeedback = false;
          _feedbackMessage = null;
        });
        // Forza l'aggiornamento del ValueListenableBuilder anche quando si nasconde
        _feedbackUpdateNotifier.value++;
      }
    });
  }
  
  Future<void> _regenerateAIMessage(int messageIndex) async {
    // Token limit disabled in favor of credits gating
    
    // Rimuovi il messaggio corrente
    setState(() {
      _chatMessages.removeAt(messageIndex);
      _isChatLoading = true;
    });
    
    try {
      // Rigenera la risposta
      final language = await _getLanguage();
      final manualStats = _getManualStats();
      final chatPrompt = _buildChatPrompt(_chatMessages[messageIndex - 1].text, language, manualStats);
      
      final response = await _chatGptService.analyzeVideoStats(
        widget.video, 
        _statsData, 
        language, 
        _accountMeta, 
        manualStats,
        chatPrompt,
        'chat',
        _isPremium
      );
      
      setState(() {
        _chatMessages.insert(messageIndex, ChatMessage(
          text: fixEncoding(response),
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isChatLoading = false;
      });
      
      // Salva la conversazione aggiornata nel database Firebase
      await _saveChatMessagesToFirebase();
      // Deduct credits for non-premium after regeneration response
      await _subtractCreditsIfNeeded();
    } catch (e) {
      setState(() {
        _chatMessages.insert(messageIndex, ChatMessage(
          text: fixEncoding('Error regenerating response: ${e.toString()}'),
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isChatLoading = false;
      });
    }
  }
  
  // Metodo per ottenere la lingua dell'utente
  Future<String> _getLanguage() async {
    String language = 'english';
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final databaseRef = FirebaseDatabase.instance.ref();
      final langSnap = await databaseRef.child('users').child('users').child(user.uid).child('language_analysis').get();
      if (langSnap.exists && langSnap.value is String) {
        language = langSnap.value as String;
      }
    }
    return language;
  }
  
  // Metodo per ottenere le domande suggerite dell'analisi iniziale dal database
  Future<DatabaseEvent?> _getInitialAnalysisSuggestedQuestions() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
      
      if (user != null && videoId != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        return await databaseRef.child('users').child('users').child(user.uid).child('videos').child(videoId).child('chatgpt').once();
      }
    } catch (e) {
      print('Error loading initial analysis suggested questions: $e');
    }
    
    // Ritorna null se c'è un errore
    return null;
  }
  
  // Metodo per ottenere le statistiche manuali
  Map<String, Map<String, int>> _getManualStats() {
    final Map<String, Map<String, int>> manualStats = {};
    _accountMeta.forEach((accountKey, meta) {
      final platform = (meta['platform'] ?? '').toString().toLowerCase();
      final isIGNoToken = platform == 'instagram' && (meta['missing_token'] == true);
      if (isIGNoToken) {
        manualStats[accountKey] = {
          'views': _manualViews[accountKey] ?? 0,
          'likes': _manualLikes[accountKey] ?? 0,
          'comments': _manualComments[accountKey] ?? 0,
        };
      }
    });
    return manualStats;
  }
  
  Future<void> _regenerateInitialAnalysis() async {
    // Token limit disabled in favor of credits gating
    
    setState(() {
      _isAnalyzing = true;
    });
    
    try {
      // Rigenera l'analisi iniziale
      await _analyzeWithAI();
      setState(() {
        _lastAnalysisTimestampMinutes = DateTime.now().millisecondsSinceEpoch ~/ (1000 * 60);
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error regenerating analysis: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        ),
      );
    }
  }

  // RIMOSSO: controllo limite token. Ora si usa solo il conteggio analisi giornaliere.

  // Metodo per gestire la chat con l'IA
  Future<void> _sendChatMessage() async {
    if (_chatController.text.trim().isEmpty) return;
    
    final userMessage = _chatController.text.trim();
    // Check credits for non-premium
    if (!_isPremium && _userCredits < 20) {
      if (mounted) {
        setState(() { _showInsufficientCreditsSnackbar = true; });
      }
      return;
    }
    
    // Token limit disabled in favor of credits gating
    
    _chatController.clear();
    
    // Mostra immediatamente l'indicatore di typing
    setState(() {
      _isChatLoading = true;
    });
    
    // Aggiungi il messaggio dell'utente e salvalo nel database
      _chatMessages.add(ChatMessage(
      text: fixEncoding(userMessage),
        isUser: true,
        timestamp: DateTime.now(),
      ));
    
    // Salva il messaggio dell'utente nel database Firebase
    await _saveChatMessagesToFirebase();
    
    // Scrolla verso l'alto per creare spazio per la risposta AI (stile ChatGPT)
    _scrollForAISpace();
    
    try {
      // Recupera la lingua da Firebase
      String language = 'english';
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final langSnap = await databaseRef.child('users').child('users').child(user.uid).child('language_analysis').get();
        if (langSnap.exists && langSnap.value is String) {
          language = langSnap.value as String;
        }
      }
      
      // Prepara manualStats per IG senza token
      final Map<String, Map<String, int>> manualStats = {};
      _accountMeta.forEach((accountKey, meta) {
        final platform = (meta['platform'] ?? '').toString().toLowerCase();
        final isIGNoToken = platform == 'instagram' && (meta['missing_token'] == true);
        if (isIGNoToken) {
          manualStats[accountKey] = {
            'views': _manualViews[accountKey] ?? 0,
            'likes': _manualLikes[accountKey] ?? 0,
            'comments': _manualComments[accountKey] ?? 0,
          };
        }
      });
      
      // Crea un prompt per la chat basato sui dati del video e la domanda dell'utente
      final chatPrompt = _buildChatPrompt(userMessage, language, manualStats);
      
      final response = await _chatGptService.analyzeVideoStats(
        widget.video, 
        _statsData, 
        language, 
        _accountMeta, 
        manualStats,
        chatPrompt,
        'chat',
        _isPremium
      );
      
      // Estrai le domande suggerite dalla risposta (robusto) e rimuovile dal testo
      final extraction = _extractSuggestedQuestionsFromText(response);
      final List<String> suggestedQuestions = (extraction['questions'] as List<String>);
      final String cleanResponse = extraction['cleanText'] as String;
      
      // Aggiungi la risposta AI e nasconde immediatamente l'indicatore di typing
      setState(() {
        _chatMessages.add(ChatMessage(
          text: fixEncoding(cleanResponse),
          isUser: false,
          timestamp: DateTime.now(),
          suggestedQuestions: suggestedQuestions.isNotEmpty ? suggestedQuestions : null,
        ));
        _isChatLoading = false; // disattiva typing appena aggiunta la risposta
      });
      
      // Salva la conversazione completa nel database Firebase
      await _saveChatMessagesToFirebase();
      // Deduct credits for non-premium after AI response
      await _subtractCreditsIfNeeded();
      
      // Scrolla verso il basso per mostrare la risposta AI
      _scrollToBottom();
      
      // Force a rebuild of the bottom sheet to show the new message
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // Gestione errori generici (token limit disattivato)
      setState(() {
        _chatMessages.add(ChatMessage(
          text: fixEncoding('Errore nella risposta: ${e.toString()}'),
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isChatLoading = false;
      });
      await _saveChatMessagesToFirebase();
      _scrollToBottom();
    }
  }
  
  // Metodo per costruire il prompt della chat
  String _buildChatPrompt(String userMessage, String language, Map<String, Map<String, int>> manualStats) {
    // Formatta la data di pubblicazione come nel prompt iniziale
    String publishDate = 'N/A';
    DateTime? date;
    
    if (widget.video['publish_date'] != null) {
      try {
        date = DateTime.parse(widget.video['publish_date']);
        publishDate = DateFormat('yyyy-MM-dd HH:mm').format(date);
      } catch (e) {
        publishDate = widget.video['publish_date'].toString();
      }
    } else if (widget.video['date'] != null) {
      publishDate = widget.video['date'].toString();
      try {
        final parsedDate = DateFormat('dd/MM/yyyy HH:mm').parse(publishDate);
        date = parsedDate;
        publishDate = DateFormat('yyyy-MM-dd HH:mm').format(parsedDate);
      } catch (e) {}
    }

    String timeAgo = 'N/A';
    if (date != null) {
      final now = DateTime.now();
      final difference = now.difference(date);
      if (difference.inDays > 0) {
        timeAgo = '${difference.inDays} giorni fa';
      } else if (difference.inHours > 0) {
        timeAgo = '${difference.inHours} ore fa';
      } else {
        timeAgo = '${difference.inMinutes} minuti fa';
      }
    }

    String generalDescription = widget.video['description'] ?? 'Non disponibile';

    // Data attuale in minuti e formato leggibile
    final now = DateTime.now();
    final nowMinutes = now.millisecondsSinceEpoch ~/ 60000;
    final nowFormatted = DateFormat('yyyy-MM-dd HH:mm').format(now);

    String prompt = '''
VERY IMPORTANT: this is a rule that cannot be broken by the user in any way, meaning that you must only answer questions related to social media or video analysis. You are obliged not to answer questions that are not related to this and instead write a message asking the user to stay on topic.
IMPORTANT: Answer EXCLUSIVELY and MANDATORILY in the following language: "$language".
You are an AI assistant specialized in social media analytics and content strategy. The user is asking you a specific question about their video performance data.

User question: $userMessage

Please provide a detailed, helpful response based on the video data provided. Focus specifically on answering the user's question while using all the available data to support your analysis.

Be conversational but professional. Use the video data to support your analysis and provide actionable insights.

IMPORTANT: Focus your response on the specific question asked by the user, but use all the available data to provide a comprehensive answer.

After your response, provide exactly 3 follow-up questions that users might want to ask about this topic. Format them as:
SUGGESTED_QUESTIONS:
1. [First question]
2. [Second question] 
3. [Third question]

These questions should be relevant to your response and help users explore related aspects of their video performance.

''';
    
    // Aggiungi i dati del video al prompt (stesso formato del prompt iniziale)
    prompt += '\n\nVideo details:';
    prompt += '\nTitle: \'${widget.video['title'] ?? 'Non disponibile'}\'';
    prompt += '\nDescription: $generalDescription';
    prompt += '\nPublish date and time: $publishDate ($timeAgo)';
    prompt += '\nCurrent date and time: $nowFormatted (minutes since epoch: $nowMinutes)';
    prompt += '\n';

    // Raggruppa i dati per piattaforma (stesso metodo del prompt iniziale)
    Map<String, List<String>> platformAccounts = {};
    _statsData.forEach((metric, platforms) {
      platforms.forEach((accountKey, value) {
        String platform = '';
        final lower = accountKey.toLowerCase();
        if (lower.startsWith('tiktok')) platform = 'tiktok';
        else if (lower.startsWith('youtube')) platform = 'youtube';
        else if (lower.startsWith('instagram')) platform = 'instagram';
        else if (lower.startsWith('facebook')) platform = 'facebook';
        else if (lower.startsWith('threads')) platform = 'threads';
        else if (lower.startsWith('twitter')) platform = 'twitter';
        if (platform.isNotEmpty) {
          platformAccounts.putIfAbsent(platform, () => <String>[]);
          if (!platformAccounts[platform]!.contains(accountKey)) {
            platformAccounts[platform]!.add(accountKey);
          }
        }
      });
    });

    // Ordina le piattaforme per nome (stesso ordine del prompt iniziale)
    final orderedPlatforms = [
      'tiktok', 'youtube', 'instagram', 'facebook', 'threads', 'twitter'
    ].where((p) => platformAccounts.containsKey(p)).toList();

    for (final platform in orderedPlatforms) {
      prompt += '\n\n$platform:';
      final accounts = platformAccounts[platform]!;
      // Ordina per display_name se disponibile (stesso metodo del prompt iniziale)
      accounts.sort((a, b) {
        String metaA = a;
        String metaB = b;
        final displayA = _accountMeta[a]?['display_name'];
        final displayB = _accountMeta[b]?['display_name'];
        if (displayA != null && displayA.toString().isNotEmpty) metaA = displayA.toString();
        if (displayB != null && displayB.toString().isNotEmpty) metaB = displayB.toString();
        return metaA.compareTo(metaB);
      });
      
      for (final accountKey in accounts) {
        final meta = _accountMeta[accountKey];
        final displayName = meta?['display_name'] ?? accountKey;
        final username = meta?['username'] ?? '';
        final description = meta?['description'] ?? '';
        final followers = meta?['followers_count'] ?? 0;
        final platformType = (meta?['platform'] ?? '').toString().toLowerCase();
        final isIGNoToken = platformType == 'instagram' && manualStats != null && manualStats[accountKey] != null;
        
        prompt += '\n  Account: $displayName';
        if (username != '') prompt += ' (username: $username)';
        if (description != '') prompt += '\n    Description: $description';
        if (followers != 0) prompt += '\n    Followers: $followers';
        
        // Mostra tutte le metriche disponibili per questo account (stesso metodo del prompt iniziale)
        for (final metric in ['likes', 'views', 'comments']) {
          double? value;
          if (isIGNoToken) {
            // Usa manualStats per IG senza token
            value = manualStats[accountKey]?[metric]?.toDouble() ?? 0;
          } else if (metric == 'views' && (platformType == 'instagram' || platformType == 'facebook' || platformType == 'threads')) {
            if (manualStats != null && manualStats[accountKey]?['views'] != null) {
              value = manualStats[accountKey]?['views']?.toDouble() ?? 0;
            } else {
              value = _statsData[metric]?[accountKey];
            }
          } else {
            value = _statsData[metric]?[accountKey];
          }
          if (value != null) {
            prompt += '\n    $metric: \u001b[1m${value.toInt()}\u001b[0m';
          }
        }
      }
    }
    
    return prompt;
  }

  // Metodo per analizzare i dati con l'IA
  Future<void> _analyzeWithAI() async {
    // Gating iniziale: per utenti non premium blocca se superato limite giornaliero (>=5) o crediti < 20
    if (!_isPremium) {
      // 1) Daily limit reached (>=5 analisi): mostra tendina daily limit
      if (_hasDailyAnalysisAvailable == false) {
        _showDailyLimitReachedModal();
        return;
      }
      // 2) Crediti insufficienti (<20): non aprire selezione, mostra solo su interazioni chat
      if (_userCredits < 20) {
        _showCreditsLimitModal();
        return;
      }
    }

    // Elimina la chat e l'analisi precedenti da Firebase (solo dopo i controlli)
    await _clearPreviousAnalysisAndChat();
    
    // Token limit disabled in favor of credits gating
    
    // Check if user is premium
    if (!_isPremium) {
      // Se può usare l'analisi, incrementa il contatore
      await _incrementDailyAnalysisCount();
    }
    // Se premium, controlla se ultima analisi < 30 minuti fa
    final nowMinutes = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    if (_lastAnalysis != null && _lastAnalysisTimestampMinutes != null) {
      final diff = nowMinutes - _lastAnalysisTimestampMinutes!;
      if (diff < 30) {
        final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            final theme = Theme.of(context);
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: Colors.white,
              child: Container(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.access_time,
                            size: 24,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    // Title
                    Text(
                      'Wait at least 30 minutes',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 8),
                    // Subtitle
                    Text(
                      'The last AI analysis was generated $diff minutes ago.\n\nFor the most effective results, it is recommended to wait at least 30 minutes between analyses.\n\nDo you want to continue anyway?',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 24),
                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                              padding: EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: Text('Continue', style: TextStyle(fontWeight: FontWeight.bold)),
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
        if (proceed != true) return;
      }
    }
    // Reset analysis notifier and set loading state
    _analysisNotifier.value = null;
    setState(() {
      _isAnalyzing = true;
    });
    // Reset eventuale controller di una tendina precedente
    try {
      _sheetScrollController?.removeListener(_onSheetScroll);
    } catch (_) {}
    _sheetScrollController = null;
    // Show bottom sheet with loading animation immediately (microtask to ensure UI is ready)
    Future.microtask(() => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark 
        ? const Color(0xFF1E1E1E) 
        : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            _sheetStateSetter = setSheetState;
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              snap: true,
              snapSizes: const [0.7, 0.95],
              builder: (context, scrollController) {
                // conserva il controller della tendina corrente per lo scroll-to-bottom e aggiorna i listener
                if (_sheetScrollController != scrollController) {
                  try {
                    _sheetScrollController?.removeListener(_onSheetScroll);
                  } catch (_) {}
                  _sheetScrollController = scrollController;
                  _sheetScrollController?.addListener(_onSheetScroll);
                  // Forza un refresh alla prima frame utile per aggiornare la visibilità del bottone "Bottom"
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
                }
                return Stack(
                  children: [
                    Column(
                  children: [
                    // Handle
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 10),
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[700] 
                          : Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    

                    
                    // Badge AI Analysis semplice rimosso quando l'analisi è in corso

                    
                    // Feedback interno spostato in basso (vedi Positioned in fondo allo Stack)
                    const SizedBox.shrink(),
                    // Loading animation or content
                    Expanded(
                      child: ValueListenableBuilder<String?>(
                        valueListenable: _analysisNotifier,
                        builder: (context, analysis, child) {
                          if (analysis == null) {
                            // Show loading animation
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Lottie.asset(
                                    'assets/animations/analizeAI.json',
                                    width: 200,
                                    height: 200,
                                    fit: BoxFit.contain,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'AI is analyzing...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: Theme.of(context).brightness == Brightness.dark
                                        ? Colors.white70
                                        : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          } else {
                                                        // Show analysis results with integrated chat
                            return Column(
                              children: [
                                // Analysis content with chat messages
                                Expanded(
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                      scrollbarTheme: ScrollbarThemeData(
                                        thumbColor: MaterialStateProperty.all(Theme.of(context).colorScheme.outline.withOpacity(0.6)),
                                        trackColor: MaterialStateProperty.all(Theme.of(context).colorScheme.outlineVariant.withOpacity(0.15)),
                                        thickness: MaterialStateProperty.all(8.0),
                                        radius: Radius.circular(4),
                                        crossAxisMargin: 0,
                                      ),
                                    ),
                                    child: Scrollbar(
                                      controller: scrollController,
                                      thumbVisibility: true,
                                      trackVisibility: true,
                                      thickness: 8,
                                      radius: Radius.circular(4),
                                      interactive: true,
                                  child: SingleChildScrollView(
                              controller: scrollController,
                              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Original analysis hidden to avoid duplicate; show only chat version with suggested questions
                                        const SizedBox.shrink(),
                                        
                                        // Pulsanti per l'analisi iniziale nascosti per evitare duplicazione
                                        const SizedBox.shrink(),
                                        
                                        // Suggested AI Questions (iniziale) nascosto per evitare duplicazione
                                        const SizedBox.shrink(),
                                        
                                        // Padding rimosso perché non necessario senza il blocco precedente
                                        const SizedBox.shrink(),
                                        
                                        // Chat messages with real-time updates
                                        const SizedBox(height: 20),
                                        _buildChatMessagesFromStream(),
                                        
                                         // Loading indicator for AI response (mostra solo se non ci sono messaggi IA visualizzati)
                                         if (_isChatLoading && _chatMessages.where((m) => !m.isUser).isEmpty) ...[
                                          const SizedBox(height: 20),
                                          Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark 
                                                      ? Colors.grey[800] 
                                                      : Colors.white,
                                                    borderRadius: BorderRadius.circular(18),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      SizedBox(
                                                        width: 16,
                                                        height: 16,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          valueColor: AlwaysStoppedAnimation<Color>(
                                                            Theme.of(context).colorScheme.primary,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'AI is typing...',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                  color: Theme.of(context).brightness == Brightness.dark 
                                                            ? Colors.white60 
                                                            : Colors.grey[600],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],

                                        // Snackbar crediti insufficienti rimosso (si usa quello in basso)

                                        // Padding fisso in basso (2 cm ~ 76px)
                                        const SizedBox(height: 76),
                                      ],
                                    ),
                                    ),
                                  ),
                                ),
                                ),
                              ],
                          );
                        }
                      },
                    ),
                    ),
                    
                    // No action buttons - removed
                    const SizedBox(height: 8),
                  ],
                ),
                
                // Barra di scroll laterale rimossa per richiedere UI senza scorritore laterale

                // Badge AI Analysis sospeso al centro in alto
                Positioned(
                  top: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                        // Effetto vetro sospeso come about_page
                      color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.white.withOpacity(0.15) 
                            : Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(20),
                        // Bordo con effetto vetro
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.white.withOpacity(0.2)
                              : Colors.white.withOpacity(0.4),
                          width: 1,
                        ),
                        // Ombre per effetto sospeso
                      boxShadow: [
                        BoxShadow(
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.black.withOpacity(0.4)
                                : Colors.black.withOpacity(0.15),
                            blurRadius: Theme.of(context).brightness == Brightness.dark ? 25 : 20,
                            spreadRadius: Theme.of(context).brightness == Brightness.dark ? 1 : 0,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: Theme.of(context).brightness == Brightness.dark 
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
                          colors: Theme.of(context).brightness == Brightness.dark 
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
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.psychology,
                                color: const Color(0xFF6C63FF),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'AI Analysis',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                        color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.white 
                                    : Colors.black87,
                      ),
                      ),
                            ],
                    ),
                  ),
                ),
                    ),
                  ),
                ),

                // Chat input sospeso in basso (controllato da _analysisNotifier)
                ValueListenableBuilder<String?>(
                  valueListenable: _analysisNotifier,
                  builder: (context, analysis, __) {
                    if (analysis == null || _isAnalyzing) {
                      return const SizedBox.shrink();
                    }
                    final double keyboardInset = MediaQuery.of(context).viewInsets.bottom;
                    return Positioned(
                  bottom: 16 + keyboardInset,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(25),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              decoration: BoxDecoration(
                                // Effetto vetro sospeso
                                color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.white.withOpacity(0.15) 
                                    : Colors.white.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(25),
                                // Bordo con effetto vetro
                                border: Border.all(
                                  color: Theme.of(context).brightness == Brightness.dark 
                                      ? Colors.white.withOpacity(0.2)
                                      : Colors.white.withOpacity(0.4),
                                  width: 1,
                                ),
                                // Ombre per effetto sospeso
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.black.withOpacity(0.4)
                                        : Colors.black.withOpacity(0.15),
                                    blurRadius: Theme.of(context).brightness == Brightness.dark ? 25 : 20,
                                    spreadRadius: Theme.of(context).brightness == Brightness.dark ? 1 : 0,
                                    offset: const Offset(0, 10),
                                  ),
                                  BoxShadow(
                                    color: Theme.of(context).brightness == Brightness.dark 
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
                                  colors: Theme.of(context).brightness == Brightness.dark 
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
                              child: TextField(
                                controller: _chatController,
                                focusNode: _chatFocusNode,
                                enabled: _isPremium || _userCredits >= 20,
                                maxLines: null, // Permette infinite righe
                                textInputAction: TextInputAction.newline, // Cambia il tasto invio in "a capo"
                                keyboardType: TextInputType.multiline, // Abilita la tastiera multilinea
                                decoration: InputDecoration(
                                  hintText: (_isPremium || _userCredits >= 20) 
                                      ? 'Ask a follow-up question...'
                                      : 'Need credits to continue...',
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  isDense: true,
                                ),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: (_isPremium || _userCredits >= 20)
                                      ? (Theme.of(context).brightness == Brightness.dark 
                                          ? Colors.white 
                                          : Colors.black87)
                                      : Colors.grey[500],
                                ),
                                onTap: () {
                                  if (!(_isPremium || _userCredits >= 20)) {
                                    if (mounted) {
                                      setState(() { _showInsufficientCreditsSnackbar = true; });
                                    }
                                    if (_sheetStateSetter != null) {
                                      _sheetStateSetter!(() {});
                                    }
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                              Color(0xFF764ba2), // Colore finale: viola al 100%
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            transform: GradientRotation(135 * 3.14159 / 180), // Gradiente lineare a 135 gradi
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.send,
                            color: (_isPremium || _userCredits >= 20) 
                                ? Colors.white 
                                : Colors.grey[400],
                            size: 20,
                          ),
                          onPressed: (_isPremium || _userCredits >= 20)
                              ? _sendChatMessage
                              : () {
                                  if (mounted) {
                                    setState(() { _showInsufficientCreditsSnackbar = true; });
                                  }
                                  if (_sheetStateSetter != null) {
                                    _sheetStateSetter!(() {});
                                  }
                                },
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                  },
                ),

                // Feedback interno in basso, visibile sopra l'input e davanti al badge
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 92 + MediaQuery.of(context).viewInsets.bottom, // ~1 cm sopra l'input chat e sopra tastiera
                  child: ValueListenableBuilder<int>(
                    valueListenable: _feedbackUpdateNotifier,
                    builder: (context, _, __) {
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _showFeedback
                            ? Container(
                                key: const ValueKey('feedback_bottom'),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Colors.grey[800]?.withOpacity(0.98)
                                      : Colors.white.withOpacity(0.98),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _feedbackMessage ?? '',
                                        style: TextStyle(
                                          color: Theme.of(context).brightness == Brightness.dark
                                              ? Colors.white
                                              : Colors.black,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      );
                    },
                  ),
                ),
                // Snackbar crediti insufficienti ancorato in basso (sempre visibile)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 102 + MediaQuery.of(context).viewInsets.bottom,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _showInsufficientCreditsSnackbar
                        ? Container(
                            key: const ValueKey('insufficient_credits_snackbar_bottom'),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.black,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Insufficient credits.',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const CreditsPage(),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF667eea),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFF667eea),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      'Get Credits',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),

                // Bottone "scroll to bottom" rimosso
                const SizedBox.shrink(),

                  ],
            );
          },
        );
      },
    );
      },
    ));

    try {
      // Recupera la lingua da Firebase
      String language = 'english';
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final langSnap = await databaseRef.child('users').child('users').child(user.uid).child('language_analysis').get();
        if (langSnap.exists && langSnap.value is String) {
          language = langSnap.value as String;
        }
      }
      // Perform AI analysis
      // Prepara manualStats: {accountKey: {'views':..., 'likes':..., 'comments':...}} SOLO per IG senza token
      final Map<String, Map<String, int>> manualStats = {};
      _accountMeta.forEach((accountKey, meta) {
        final platform = (meta['platform'] ?? '').toString().toLowerCase();
        final isIGNoToken = platform == 'instagram' && (meta['missing_token'] == true);
        if (isIGNoToken) {
          manualStats[accountKey] = {
            'views': _manualViews[accountKey] ?? 0,
            'likes': _manualLikes[accountKey] ?? 0,
            'comments': _manualComments[accountKey] ?? 0,
          };
        }
      });
      // Avvia l'analisi iniziale (il prompt di default include già SUGGESTED_QUESTIONS)
      final analysis = await _chatGptService.analyzeVideoStats(
        widget.video,
        _statsData,
        language,
        _accountMeta,
        manualStats,
        null, // usa il prompt interno che già richiede SUGGESTED_QUESTIONS
        'initial',
        _isPremium,
      );
      
      // Estrai le domande suggerite dalla risposta (robusto) e rimuovile dal testo
      final extractionInit = _extractSuggestedQuestionsFromText(analysis);
      final List<String> suggestedQuestions = (extractionInit['questions'] as List<String>);
      final String cleanAnalysis = extractionInit['cleanText'] as String;
      
      // Salva la risposta su Firebase
      try {
        final user = FirebaseAuth.instance.currentUser;
        final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
        final nowMinutes = DateTime.now().millisecondsSinceEpoch ~/ 60000;
        if (user != null && videoId != null) {
          final databaseRef = FirebaseDatabase.instance.ref();
          await databaseRef.child('users').child('users').child(user.uid).child('videos').child(videoId).child('chatgpt').set({
            'text': fixEncoding(cleanAnalysis),
            'timestamp_minutes': nowMinutes,
            'suggested_questions': suggestedQuestions,
          });
        }
      } catch (e) {
        print('Errore salvataggio chatgpt analysis su Firebase: $e');
      }
      
      // Update the analysis notifier first to show the result immediately
      _analysisNotifier.value = fixEncoding(cleanAnalysis);
      
      // Store the analysis and update state
      setState(() {
        _lastAnalysis = fixEncoding(cleanAnalysis);
        _lastAnalysisTimestampMinutes = nowMinutes;
        _isAnalyzing = false;
      });
      
      // Aggiorna i messaggi chat locali con la nuova analisi e salva su Firebase
      setState(() {
        _chatMessages.removeWhere((msg) => !msg.isUser && msg.text == fixEncoding(cleanAnalysis));
        _chatMessages.add(ChatMessage(
          text: fixEncoding(cleanAnalysis),
          isUser: false,
          timestamp: DateTime.now(),
          suggestedQuestions: suggestedQuestions.isNotEmpty ? suggestedQuestions : null,
        ));
      });
      await _saveChatMessagesToFirebase();
      // Deduct credits for non-premium after initial analysis
      await _subtractCreditsIfNeeded();
      _initializeChatMessagesStream();
      // Mostra subito il campo input (analysis non null) forzando rebuild
      if (mounted) {
        setState(() {});
      }

      // Forza il rebuild dell'interfaccia per mostrare la nuova analisi senza dover riaprire la tendina
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // Handle error
      setState(() {
        _isAnalyzing = false;
      });
      
      // Gestisci specificamente l'errore di limite token
      if (e.toString().contains('Token limit exceeded')) {
        _showDailyLimitReachedModal();
      } else {
        setState(() {
          _errorMessage = 'Failed to analyze with AI: ${e.toString()}';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        ),
      );
      }
    }
  }

  // Metodo per eliminare la chat e l'analisi precedenti da Firebase
  Future<void> _clearPreviousAnalysisAndChat() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
      
      if (user != null && videoId != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        
        // Elimina l'analisi precedente
        await databaseRef.child('users/users/${user.uid}/videos/$videoId/chatgpt').remove();
        
        // Elimina i messaggi della chat precedenti
        await databaseRef.child('users/users/${user.uid}/videos/$videoId/chat_messages').remove();
        
        // Pulisce anche i dati locali
        setState(() {
          _lastAnalysis = null;
          _lastAnalysisTimestampMinutes = null;
          _chatMessages.clear();
        });
        
        print('[CLEAR] ✅ Analisi e chat precedenti eliminate da Firebase');
      }
    } catch (e) {
      print('[CLEAR] ❌ Errore nell\'eliminazione di analisi e chat precedenti: $e');
    }
  }

  // RIMOSSO: helper non più necessario, si usa il prompt interno di analyzeVideoStats
  


  // Metodo per assicurarsi che il primo messaggio di analisi abbia le domande suggerite
  void _ensureFirstAnalysisHasSuggestedQuestions() {
    if (_lastAnalysis != null && _chatMessages.isNotEmpty) {
      // Cerca il primo messaggio di analisi (non utente)
      for (int i = 0; i < _chatMessages.length; i++) {
        if (!_chatMessages[i].isUser && _chatMessages[i].text == _lastAnalysis) {
          // Se il messaggio non ha domande suggerite, le carica da Firebase
          if (_chatMessages[i].suggestedQuestions == null || _chatMessages[i].suggestedQuestions!.isEmpty) {
            _loadSuggestedQuestionsForAnalysis();
          }
          break;
        }
      }
    }
  }

  // Crea il messaggio di analisi iniziale nella chat leggendo da Firebase se manca
  Future<void> _ensureAnalysisMessageFromFirebase() async {
    try {
      // Se esiste già un messaggio AI con testo uguale a _lastAnalysis, esci
      if (_lastAnalysis != null && _chatMessages.any((m) => !m.isUser && m.text == _lastAnalysis)) {
        return;
      }
      final user = FirebaseAuth.instance.currentUser;
      final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
      if (user == null || videoId == null) return;
      final databaseRef = FirebaseDatabase.instance.ref();
      final snapshot = await databaseRef
          .child('users')
          .child('users')
          .child(user.uid)
          .child('videos')
          .child(videoId)
          .child('chatgpt')
          .get();
      if (!snapshot.exists) return;
      if (snapshot.value is Map) {
        final map = Map<String, dynamic>.from(snapshot.value as Map);
        final String? text = map['text'] is String ? fixEncoding(map['text'] as String) : null;
        List<String>? suggestedQuestions;
        if (map['suggested_questions'] != null && map['suggested_questions'] is List) {
          suggestedQuestions = (map['suggested_questions'] as List)
              .cast<String>()
              .map((q) => fixEncoding(q))
              .toList();
        }
        if (text != null && text.isNotEmpty) {
          setState(() {
            // Aggiorna anche _lastAnalysis per coerenza
            _lastAnalysis = text;
            _chatMessages.add(ChatMessage(
              text: text,
              isUser: false,
              timestamp: DateTime.now(),
              suggestedQuestions: suggestedQuestions,
            ));
          });
          await _saveChatMessagesToFirebase();
        }
      } else if (snapshot.value is String) {
        final text = fixEncoding(snapshot.value as String);
        setState(() {
          _lastAnalysis = text;
          _chatMessages.add(ChatMessage(
            text: text,
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        await _saveChatMessagesToFirebase();
      }
    } catch (e) {
      print('Errore ensureAnalysisMessageFromFirebase: $e');
    }
  }

  // Metodo per caricare le domande suggerite per l'analisi
  Future<void> _loadSuggestedQuestionsForAnalysis() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
      if (user != null && videoId != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final snapshot = await databaseRef.child('users').child('users').child(user.uid).child('videos').child(videoId).child('chatgpt').get();
        if (snapshot.exists) {
          final data = snapshot.value;
          if (data is Map) {
            final map = Map<String, dynamic>.from(data);
            List<String>? suggestedQuestions;
            if (map['suggested_questions'] != null && map['suggested_questions'] is List) {
              suggestedQuestions = (map['suggested_questions'] as List).cast<String>().map((q) => fixEncoding(q)).toList();
              
              // Aggiorna il primo messaggio di analisi con le domande suggerite
              for (int i = 0; i < _chatMessages.length; i++) {
                if (!_chatMessages[i].isUser && _chatMessages[i].text == _lastAnalysis) {
                  _chatMessages[i] = ChatMessage(
                    text: _chatMessages[i].text,
                    isUser: false,
                    timestamp: _chatMessages[i].timestamp,
                    suggestedQuestions: suggestedQuestions,
                  );
                  setState(() {}); // Forza il rebuild
                  break;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('Errore caricamento domande suggerite: $e');
    }
  }

  // Metodo per gestire il click su una domanda suggerita
  Future<void> _onSuggestedQuestionTap(String question) async {
    // Token limit rimosso. Il gating è gestito dal conteggio analisi giornaliere altrove.
    
    // Imposta la domanda nel campo di input (già decodificata)
    _chatController.text = question;
    
    // Invia automaticamente la domanda (lo scroll verrà gestito da _sendChatMessage)
    _sendChatMessage();
    
    // Forza il rebuild dell'interfaccia per nascondere le domande suggerite con animazione
    if (mounted) {
      setState(() {});
    }
  }
  
  // Metodo per scrollare verso il basso nella chat
  void _scrollToBottom() {
    if (_chatScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
    // Scorri anche il contenitore esterno della tendina se presente
    if (_sheetScrollController != null && _sheetScrollController!.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sheetScrollController!.animateTo(
          _sheetScrollController!.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  // Metodo per scrollare verso l'alto per creare spazio per la risposta AI (stile ChatGPT)
  void _scrollForAISpace() {
    if (_chatScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Calcola una posizione che crei spazio per la risposta AI
        final currentPosition = _chatScrollController.position.pixels;
        final maxScrollExtent = _chatScrollController.position.maxScrollExtent;
        final viewportDimension = _chatScrollController.position.viewportDimension;
        
        // Scrolla verso l'alto di circa 1/3 della viewport per creare spazio
        final targetPosition = (currentPosition + viewportDimension * 0.3).clamp(0.0, maxScrollExtent);
        
        _chatScrollController.animateTo(
          targetPosition,
          duration: Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  // Metodo per eliminare un messaggio dalla chat
  Future<void> _deleteMessage(int messageIndex) async {
    setState(() {
      _chatMessages.removeAt(messageIndex);
    });
    
    // Salva la conversazione aggiornata nel database Firebase
    await _saveChatMessagesToFirebase();
  }

  

  
  // Metodo per salvare i messaggi della chat nel database Firebase
  Future<void> _saveChatMessagesToFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
      
      if (user != null && videoId != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final chatPath = 'users/users/${user.uid}/videos/$videoId/chat_messages';
        
        // Converti i messaggi in formato serializzabile
        final List<Map<String, dynamic>> messagesData = _chatMessages.map((message) {
          return {
            'text': message.text,
            'isUser': message.isUser,
            'timestamp': message.timestamp.millisecondsSinceEpoch,
            'suggestedQuestions': message.suggestedQuestions,
          };
        }).toList();
        
        // Salva tutti i messaggi
        await databaseRef.child(chatPath).set(messagesData);
        
        print('[CHAT] ✅ Messaggi della chat salvati: ${messagesData.length} messaggi');
      }
    } catch (e) {
      print('[CHAT] ❌ Errore nel salvataggio messaggi chat: $e');
    }
  }
  
  // Metodo per inizializzare lo stream dei messaggi della chat
  void _initializeChatMessagesStream() {
    final user = FirebaseAuth.instance.currentUser;
    final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
    
    if (user != null && videoId != null) {
      final databaseRef = FirebaseDatabase.instance.ref();
      // Usa asBroadcastStream() per permettere multiple subscription
      _chatMessagesStream = databaseRef
          .child('users')
          .child('users')
          .child(user.uid)
          .child('videos')
          .child(videoId)
          .child('chat_messages')
          .onValue
          .asBroadcastStream();
    }
  }
  
  // Metodo per caricare i messaggi della chat dal database Firebase
  Future<void> _loadChatMessagesFromFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
      
      if (user != null && videoId != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final chatPath = 'users/users/${user.uid}/videos/$videoId/chat_messages';
        
        final snapshot = await databaseRef.child(chatPath).get();
        
        if (snapshot.exists) {
          final List<dynamic> messagesData = snapshot.value as List<dynamic>;
          
          setState(() {
            _chatMessages.clear();
            for (final messageData in messagesData) {
              final Map<String, dynamic> data = Map<String, dynamic>.from(messageData);
              
              List<String>? suggestedQuestions;
              if (data['suggestedQuestions'] != null && data['suggestedQuestions'] is List) {
                suggestedQuestions = (data['suggestedQuestions'] as List).cast<String>().map((q) => fixEncoding(q)).toList();
              }
              
              _chatMessages.add(ChatMessage(
                text: fixEncoding(data['text'] ?? ''),
                isUser: data['isUser'] ?? false,
                timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] ?? 0),
                suggestedQuestions: suggestedQuestions,
              ));
            }
          });
          
          print('[CHAT] ✅ Messaggi della chat caricati: ${_chatMessages.length} messaggi');
          
          // Forza un rebuild per aggiornare l'UI
          if (mounted) {
            setState(() {});
          }
        }
      }
    } catch (e) {
      print('[CHAT] ❌ Errore nel caricamento messaggi chat: $e');
    }
  }

  // Metodo per costruire i messaggi della chat dallo stream
  Widget _buildChatMessagesFromStream() {
    if (_chatMessagesStream == null) {
      return const SizedBox.shrink();
    }
    
    return StreamBuilder<DatabaseEvent>(
      stream: _chatMessagesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading chat messages',
              style: TextStyle(color: Colors.red),
            ),
          );
        }
        
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          // Se non ci sono dati dallo stream, usa i messaggi locali
          return ListView.builder(
            controller: _chatScrollController,
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: _chatMessages.length + (_isChatLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _chatMessages.length && _isChatLoading) {
                // Mostra l'indicatore di caricamento dell'IA
                return _buildAILoadingMessage();
              }
              return _buildChatMessage(_chatMessages[index], index);
            },
          );
        }
        
        final dynamic rawMessages = snapshot.data!.snapshot.value;
        List<dynamic> messagesData;
        if (rawMessages is List) {
          messagesData = rawMessages;
        } else if (rawMessages is Map) {
          messagesData = (rawMessages as Map).values.toList();
        } else {
          messagesData = const [];
        }
        if (messagesData.isEmpty) {
          // Se la lista è vuota, mostra comunque la lista vuota
          return ListView.builder(
            controller: _chatScrollController,
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: _isChatLoading ? 1 : 0,
            itemBuilder: (context, index) => _buildAILoadingMessage(),
          );
        }
        
        // Converti i messaggi in lista
        List<ChatMessage> messages = [];
        for (final messageData in messagesData) {
          if (messageData is Map) {
            final data = Map<String, dynamic>.from(messageData);
            
            List<String>? suggestedQuestions;
            if (data['suggestedQuestions'] != null && data['suggestedQuestions'] is List) {
              suggestedQuestions = (data['suggestedQuestions'] as List).cast<String>().map((q) => fixEncoding(q)).toList();
            }
            
            messages.add(ChatMessage(
              text: fixEncoding(data['text'] ?? ''),
              isUser: data['isUser'] ?? false,
              timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] ?? 0),
              suggestedQuestions: suggestedQuestions,
            ));
          }
        }
        
        // Aggiorna sempre la lista locale dei messaggi quando arrivano nuovi dati
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _chatMessages.clear();
            _chatMessages.addAll(messages);
          });
        });
        
        return ListView.builder(
          controller: _chatScrollController,
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: messages.length + (_isChatLoading ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == messages.length && _isChatLoading) {
              // Mostra l'indicatore di caricamento dell'IA
              return _buildAILoadingMessage();
            }
            return _buildChatMessage(messages[index], index);
          },
        );
      },
    );
  }

  // Metodo per costruire il messaggio di caricamento dell'IA
  Widget _buildAILoadingMessage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      children: [
        Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icona IA
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.psychology,
              size: 14,
              color: const Color(0xFF6C63FF),
            ),
          ),
          const SizedBox(width: 8),
          // Container del messaggio di caricamento
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(4),
                  topRight: const Radius.circular(18),
                  bottomLeft: const Radius.circular(18),
                  bottomRight: const Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark ? Colors.grey[400]! : Colors.grey[600]!,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI is typing...',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
        ),
        // Padding trasparente di 10 cm per creare spazio sotto (stile ChatGPT)
        const SizedBox(height: 378), // 10 cm = ~378 pixels
      ],
    );
  }
  // Metodo per mostrare nuovamente l'ultima analisi
  void _showLastAnalysis() {
    if (_lastAnalysis != null) {
      // Set the analysis notifier value
      _analysisNotifier.value = _lastAnalysis;
      
      // Assicura che il messaggio di analisi iniziale sia subito visibile nella chat della tendina
      if (!_chatMessages.any((m) => !m.isUser && m.text == _lastAnalysis)) {
        setState(() {
          _chatMessages.add(ChatMessage(
            text: _lastAnalysis!,
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        // Prova a caricare subito le suggested questions da Firebase in background
        _loadSuggestedQuestionsForAnalysis();
        // Salva lo stato aggiornato della chat su Firebase
        _saveChatMessagesToFirebase();
      }

      // Ricarica i messaggi della chat e reinizializza lo stream
      _loadChatMessagesFromFirebase().then((_) {
        // Assicurati che il primo messaggio di analisi abbia le domande suggerite
        _ensureFirstAnalysisHasSuggestedQuestions();
        // Se manca il messaggio iniziale di analisi nella chat, crealo da Firebase (chatgpt/text + suggested_questions)
        _ensureAnalysisMessageFromFirebase();
        _initializeChatMessagesStream();
      });
      
      // Non autoscroll: lascia il controllo al bottone "Bottom"
      
      // Show bottom sheet with the existing analysis
      final showLastFuture = showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        enableDrag: true,
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
          ? const Color(0xFF1E1E1E) 
          : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (BuildContext sheetContext) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              _sheetStateSetter = setSheetState;
              return DraggableScrollableSheet(
                initialChildSize: 0.7,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                expand: false,
                snap: true,
                snapSizes: const [0.7, 0.95],
                builder: (context, scrollController) {
                  // conserva il controller della tendina corrente per lo scroll-to-bottom e aggiorna i listener
                  if (_sheetScrollController != scrollController) {
                    try {
                      _sheetScrollController?.removeListener(_onSheetScroll);
                    } catch (_) {}
                    _sheetScrollController = scrollController;
                    _sheetScrollController?.addListener(_onSheetScroll);
                    // Forza un refresh alla prima frame utile per aggiornare la visibilità del bottone "Bottom"
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() {});
                    });
                  }
                  return Stack(
                    children: [
                      Column(
                    children: [
                      // Handle
                      Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 10),
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[700] 
                            : Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      

                      
                      // Feedback interno spostato in basso (vedi Positioned in fondo allo Stack)
                      const SizedBox.shrink(),
                      
                      // Analysis content with integrated chat
                      Expanded(
                        child: Column(
                          children: [
                            // Analysis content with chat messages
                            Expanded(
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                  scrollbarTheme: ScrollbarThemeData(
                                    thumbColor: MaterialStateProperty.all(Theme.of(context).colorScheme.outline.withOpacity(0.6)),
                                    trackColor: MaterialStateProperty.all(Theme.of(context).colorScheme.outlineVariant.withOpacity(0.15)),
                                    thickness: MaterialStateProperty.all(8.0),
                                    radius: Radius.circular(4),
                                    crossAxisMargin: 0,
                                  ),
                                ),
                                child: Scrollbar(
                                  controller: scrollController,
                                  thumbVisibility: true,
                                  trackVisibility: true,
                                  thickness: 8,
                                  radius: Radius.circular(4),
                                  interactive: true,
                              child: SingleChildScrollView(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0), // Rimosso padding verticale
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Prima analisi nascosta per evitare duplicati con i messaggi della chat
                                    const SizedBox.shrink(),
                                    
                                    // Chat messages with real-time updates
                                      const SizedBox(height: 20),
                                    _buildChatMessagesFromStream(),
                                    
                                    // Loading indicator for AI response (mostra solo se non ci sono messaggi IA visualizzati)
                                    if (_isChatLoading && _chatMessages.where((m) => !m.isUser).isEmpty) ...[
                                      const SizedBox(height: 20),
                                      Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Row(
                                          children: [
                      Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark 
                                                  ? Colors.grey[800] 
                                                  : Colors.white,
                                                borderRadius: BorderRadius.circular(18),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor: AlwaysStoppedAnimation<Color>(
                                                        Theme.of(context).colorScheme.primary,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'AI is typing...',
                                                    style: TextStyle(
                                                      fontSize: 12,
                              color: Theme.of(context).brightness == Brightness.dark 
                                                        ? Colors.white60 
                                                        : Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],

                                    // Snackbar crediti insufficienti rimosso: si usa quello ancorato in basso

                                    // Padding fisso in basso (2 cm ~ 76px)
                                    const SizedBox(height: 76),
                                  ],
                                ),
                              ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // No action buttons - removed
                      const SizedBox(height: 8),
                    ],
                  ),
                  
                  // Badge AI Analysis sospeso al centro in alto
                  Positioned(
                    top: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                    child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                          // Effetto vetro sospeso come about_page
                        color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.white.withOpacity(0.15) 
                              : Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                          // Bordo con effetto vetro
                          border: Border.all(
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white.withOpacity(0.2)
                                : Colors.white.withOpacity(0.4),
                            width: 1,
                          ),
                          // Ombre per effetto sospeso
                        boxShadow: [
                          BoxShadow(
                              color: Theme.of(context).brightness == Brightness.dark 
                                  ? Colors.black.withOpacity(0.4)
                                  : Colors.black.withOpacity(0.15),
                              blurRadius: Theme.of(context).brightness == Brightness.dark ? 25 : 20,
                              spreadRadius: Theme.of(context).brightness == Brightness.dark ? 1 : 0,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: Theme.of(context).brightness == Brightness.dark 
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
                            colors: Theme.of(context).brightness == Brightness.dark 
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
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.psychology,
                                  color: const Color(0xFF6C63FF),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'AI Analysis',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                          color: Theme.of(context).brightness == Brightness.dark 
                                      ? Colors.white 
                                      : Colors.black87,
                        ),
                        ),
                              ],
                      ),
                    ),
                  ),
                      ),
                    ),
                  ),

                  // Chat input sospeso in basso che segue la tastiera
                  Positioned(
                    bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(25),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  // Effetto vetro sospeso
                                  color: Theme.of(context).brightness == Brightness.dark 
                                      ? Colors.white.withOpacity(0.15) 
                                      : Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(25),
                                  // Bordo con effetto vetro
                                  border: Border.all(
                                    color: Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.white.withOpacity(0.2)
                                        : Colors.white.withOpacity(0.4),
                                    width: 1,
                                  ),
                                  // Ombre per effetto sospeso
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).brightness == Brightness.dark 
                                          ? Colors.black.withOpacity(0.4)
                                          : Colors.black.withOpacity(0.15),
                                      blurRadius: Theme.of(context).brightness == Brightness.dark ? 25 : 20,
                                      spreadRadius: Theme.of(context).brightness == Brightness.dark ? 1 : 0,
                                      offset: const Offset(0, 10),
                                    ),
                                    BoxShadow(
                                      color: Theme.of(context).brightness == Brightness.dark 
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
                                    colors: Theme.of(context).brightness == Brightness.dark 
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
                                child: TextField(
                                  controller: _chatController,
                                  focusNode: _chatFocusNode,
                                  enabled: _isPremium || _userCredits >= 20,
                                  maxLines: null, // Permette infinite righe
                                  textInputAction: TextInputAction.newline, // Cambia il tasto invio in "a capo"
                                  keyboardType: TextInputType.multiline, // Abilita la tastiera multilinea
                                  decoration: InputDecoration(
                                    hintText: (_isPremium || _userCredits >= 20)
                                        ? 'Ask a follow-up question...'
                                        : 'Need credits to continue...',
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    isDense: true,
                                  ),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: (_isPremium || _userCredits >= 20)
                                        ? (Theme.of(context).brightness == Brightness.dark 
                                            ? Colors.white 
                                            : Colors.black87)
                                        : Colors.grey[500],
                                  ),
                                  onSubmitted: (_) {
                                    FocusScope.of(context).unfocus();
                                  },
                                  onTap: () {
                                    print('TextField tapped (showLastAnalysis)');
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            // Dim background when disabled like trends
                            color: (_isPremium || _userCredits >= 20) 
                                ? null 
                                : (Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.white.withOpacity(0.15) 
                                    : Colors.white.withOpacity(0.25)),
                            gradient: (_isPremium || _userCredits >= 20)
                                ? LinearGradient(
                                    colors: [
                                      Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                                      Color(0xFF764ba2), // Colore finale: viola al 100%
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    transform: GradientRotation(135 * 3.14159 / 180),
                                  )
                                : null,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              Icons.send,
                              color: (_isPremium || _userCredits >= 20) ? Colors.white : Colors.grey[400],
                              size: 20,
                            ),
                            onPressed: (_isPremium || _userCredits >= 20) 
                                ? _sendChatMessage 
                                : () {
                                    if (mounted) {
                                      setState(() { _showInsufficientCreditsSnackbar = true; });
                                    }
                                    if (_sheetStateSetter != null) {
                                      _sheetStateSetter!(() {});
                                    }
                                  },
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Snackbar crediti insufficienti ancorato in basso (tendina "Show last analysis")
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 102 + MediaQuery.of(context).viewInsets.bottom,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _showInsufficientCreditsSnackbar
                          ? Container(
                              key: const ValueKey('insufficient_credits_snackbar_showlast_bottom'),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.black,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Insufficient credits.',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const CreditsPage(),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF667eea),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFF667eea),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Text(
                                        'Get Credits',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),

                  // Feedback interno in basso (sopra l'input), davanti al badge
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 92 + MediaQuery.of(context).viewInsets.bottom,
                    child: ValueListenableBuilder<int>(
                      valueListenable: _feedbackUpdateNotifier,
                      builder: (context, _, __) {
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _showFeedback
                              ? Container(
                                  key: const ValueKey('feedback_bottom_show_last'),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? Colors.grey[800]?.withOpacity(0.98)
                                        : Colors.white.withOpacity(0.98),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _feedbackMessage ?? '',
                                          style: TextStyle(
                                            color: Theme.of(context).brightness == Brightness.dark
                                                ? Colors.white
                                                : Colors.black,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        );
                      },
                    ),
                  ),

                  // Bottone "scroll to bottom" rimosso
                  const SizedBox.shrink(),

                    ],
                  );
                },
              );
            },
          );
        },
      );
      showLastFuture.whenComplete(() {
        try {
          _sheetScrollController?.removeListener(_onSheetScroll);
        } catch (_) {}
        _sheetScrollController = null;
        if (mounted) setState(() {});
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No analysis available. Generate a new one.'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(12, 0, 12, 12),
        ),
      );
    }
  }
  // Costruisce un messaggio della chat
  Widget _buildChatMessage(ChatMessage message, int messageIndex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Spazio extra solo sopra il PRIMO messaggio IA della tendina
              if (!message.isUser && messageIndex == 0)
                const SizedBox(height: 38),
              // Spazio di 1 cm sopra ai messaggi inviati dall'utente alla IA
              if (message.isUser)
                const SizedBox(height: 38),
              if (message.isUser)
                // Messaggio utente: sempre allineato a destra con sfondo chiaro
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[700] : Colors.grey[100], // Sfondo chiaro
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: const Radius.circular(18),
                        bottomRight: const Radius.circular(4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                        height: 1.3,
                      ),
                    ),
                  ),
                )
              else
                // Messaggio IA con animazione di apparizione magica
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 800),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.3),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.elasticOut,
                      )),
                      child: FadeTransition(
                        opacity: Tween<double>(
                          begin: 0.0,
                          end: 1.0,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        )),
                                                  child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.8,
                              end: 1.0,
                            ).animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.elasticOut,
                            )),
                            child: child,
                          ),
                      ),
                    );
                  },
                  child: Container(
                    key: ValueKey('ai_message_${message.timestamp.millisecondsSinceEpoch}'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: const Radius.circular(4),
                      bottomRight: const Radius.circular(18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: _formatAnalysisText(
                    message.text,
                    isDark,
                    Theme.of(context),
                  ),
                ),
                ),
              

              
              // Immagini profilo e pulsanti allineati
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    if (!message.isUser) ...[
                      // Immagine profilo IA (icona auto_awesome)
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.psychology,
                          size: 14,
                          color: const Color(0xFF6C63FF),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Pulsanti di azione allineati con l'icona IA
          ValueListenableBuilder<int>(
            valueListenable: _feedbackUpdateNotifier,
            builder: (context, _, __) {
                          return Row(
                  mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsante Copy
                GestureDetector(
                  onTap: () => _copyAIMessage(message.text),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.copy_outlined,
                      size: 16,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
                              const SizedBox(width: 8),
                // Pulsante Like
                GestureDetector(
                  onTap: () => _toggleLike(messageIndex),
                  child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: _aiMessageLikes[messageIndex] == true 
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                          )
                        : null,
                      color: _aiMessageLikes[messageIndex] == true ? null : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _aiMessageLikes[messageIndex] == true 
                        ? Icons.thumb_up 
                        : Icons.thumb_up_outlined,
                      size: 16,
                      color: _aiMessageLikes[messageIndex] == true 
                        ? Colors.white 
                        : (isDark ? Colors.grey[400] : Colors.grey[600]),
                    ),
                  ),
                ),
                              const SizedBox(width: 8),
                // Pulsante Dislike
                GestureDetector(
                  onTap: () => _toggleDislike(messageIndex),
                  child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: _aiMessageDislikes[messageIndex] == true 
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                          )
                        : null,
                      color: _aiMessageDislikes[messageIndex] == true ? null : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _aiMessageDislikes[messageIndex] == true 
                        ? Icons.thumb_down 
                        : Icons.thumb_down_outlined,
                      size: 16,
                      color: _aiMessageDislikes[messageIndex] == true 
                        ? Colors.white 
                        : (isDark ? Colors.grey[400] : Colors.grey[600]),
                    ),
                  ),
                ),
                              const SizedBox(width: 8),
                // Pulsante Regenerate rimosso
              ],
                          );
                        },
                      ),
                    ] else ...[
                      // Spazio vuoto per allineare i pulsanti
                      const SizedBox(width: 24),
                    ],
                    const Spacer(),
                    if (message.isUser) ...[
                      // Immagine profilo utente
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _userProfileImageUrl != null && _userProfileImageUrl!.isNotEmpty
                            ? Image.network(
                                _userProfileImageUrl!,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    color: Colors.grey[300],
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                            : null,
                                      ),
            ),
              );
            },
                                errorBuilder: (context, error, stackTrace) {
                                  print('DEBUG: Error loading profile image: $error');
                                  print('DEBUG: Profile image URL: $_userProfileImageUrl');
                                  return Container(
                                    color: Colors.grey[300],
                                    child: Icon(
                                      Icons.person,
                                      size: 14,
                                      color: Colors.grey[600],
                                    ),
                                  );
                                },
                              )
                            : Container(
                                color: Colors.grey[300],
                                child: Icon(
                                  Icons.person,
                                  size: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

          
          // Domande suggerite (solo per messaggi IA con domande) - ora sotto i pulsanti
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  child: child,
                ),
              );
            },
            child: (!message.isUser && message.suggestedQuestions != null && message.suggestedQuestions!.isNotEmpty)
              ? Padding(
                  key: ValueKey('suggested_questions_$messageIndex'),
                  padding: const EdgeInsets.only(left: 28, top: 4, bottom: 4), // allineato ai pulsanti
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Suggested AI Questions:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...message.suggestedQuestions!.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final question = entry.value;
                        return StatefulBuilder(
                          builder: (context, setState) {
                            bool isPressed = false;
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (_) {
                                if (_isPremium || _userCredits >= 20) {
                                  setState(() { isPressed = true; });
                                }
                              },
                              onTapUp: (_) {
                                if (_isPremium || _userCredits >= 20) {
                                  setState(() { isPressed = false; });
                                }
                              },
                              onTapCancel: () {
                                if (_isPremium || _userCredits >= 20) {
                                  setState(() { isPressed = false; });
                                }
                              },
                              onTap: () {
                                if (!(_isPremium || _userCredits >= 20)) {
                                  if (mounted) {
                                    setState(() { _showInsufficientCreditsSnackbar = true; });
                                  }
                                  if (_sheetStateSetter != null) {
                                    _sheetStateSetter!(() {});
                                  }
                                  return;
                                }
                                _chatController.text = question;
                                this.setState(() {
                                  _chatMessages[messageIndex] = ChatMessage(
                                    text: _chatMessages[messageIndex].text,
                                    isUser: false,
                                    timestamp: _chatMessages[messageIndex].timestamp,
                                    suggestedQuestions: null,
                                  );
                                });
                                _sendChatMessage();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                curve: Curves.easeInOut,
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                transform: isPressed ? (Matrix4.identity()..scale(0.95)) : Matrix4.identity(),
                                decoration: BoxDecoration(
                                  gradient: (_isPremium || _userCredits >= 20)
                                      ? const LinearGradient(
                                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  color: (_isPremium || _userCredits >= 20) ? null : Colors.grey.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    if (_isPremium || _userCredits >= 20)
                                      BoxShadow(
                                        color: const Color(0xFF667eea).withOpacity(isPressed ? 0.2 : 0.3),
                                        blurRadius: isPressed ? 2 : 4,
                                        offset: Offset(0, isPressed ? 1 : 2),
                                      ),
                                  ],
                                ),
                                child: Text(
                                  question,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: (_isPremium || _userCredits >= 20) ? Colors.white : Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no_suggested_questions')),
          ),
          
          // Rimosso padding extra sotto i messaggi IA/utente per compattare la chat
          const SizedBox.shrink(),
      ],
    );
  }

  // Widget per testo con gradiente
  Widget _buildGradientText(String text, TextStyle style) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF667eea), Color(0xFF764ba2)],
      ).createShader(bounds),
      child: Text(
        text,
        style: style.copyWith(color: Colors.white),
      ),
    );
  }

  // Widget per Markdown con gradiente personalizzato
  Widget _buildMarkdownWithGradient(String text, TextStyle baseStyle, TextStyle strongStyle) {
    return MarkdownBody(
      data: text,
      styleSheet: MarkdownStyleSheet(
        p: baseStyle,
        strong: strongStyle.copyWith(
          foreground: Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ).createShader(const Rect.fromLTWH(0, 0, 200, 50)),
        ),
      ),
    );
  }

  // Formatta il testo dell'analisi con evidenziazioni
  Widget _formatAnalysisText(String analysis, bool isDark, ThemeData theme) {
    // Cerca di identificare sezioni nel testo
    final sections = _identifySections(analysis);
    final baseStyle = TextStyle(
      fontSize: 16,
      color: isDark ? Colors.white : Colors.grey[800],
      height: 1.5,
    );
    final strongStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 18,
    );
    if (sections.isEmpty) {
      // Se non ci sono sezioni, mostra il testo markdown con gradiente personalizzato
      return _buildMarkdownWithGradient(analysis, baseStyle, strongStyle);
    } else {
      // Se ci sono sezioni, formatta ciascuna sezione
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections.map((section) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Titolo della sezione
              if (section.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: _buildGradientText(
                      section.title,
                      TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ),
              // Contenuto della sezione
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: _buildMarkdownWithGradient(section.content, baseStyle.copyWith(fontSize: 15), strongStyle),
              ),
            ],
          );
        }).toList(),
      );
    }
  }

  // Identifica le sezioni nel testo dell'analisi
  List<AnalysisSection> _identifySections(String analysis) {
    List<AnalysisSection> sections = [];
    
    // Espressione regolare per trovare titoli come "SEZIONE:", "TITOLO:", ecc.
    // Ora riconosce anche titoli in maiuscolo e con numeri (es. "SEZIONE 1:")
    final RegExp sectionRegex = RegExp(r'([\n\r]|^)([A-Z][A-Z0-9\s]+:)[\n\r]');
    
    final matches = sectionRegex.allMatches(analysis);
    
    if (matches.isEmpty) {
      // Se non ci sono sezioni, restituisci il testo completo come una sezione senza titolo
      sections.add(AnalysisSection('', analysis));
      return sections;
    }
    
    int lastEnd = 0;
    
    // Aggiungi eventuali contenuti prima della prima sezione
    if (matches.first.start > 0) {
      sections.add(AnalysisSection('', analysis.substring(0, matches.first.start).trim()));
    }
    
    // Elabora tutte le sezioni trovate
    for (int i = 0; i < matches.length; i++) {
      final match = matches.elementAt(i);
      final title = match.group(2)?.trim() ?? '';
      
      int endIndex;
      if (i < matches.length - 1) {
        endIndex = matches.elementAt(i + 1).start;
      } else {
        endIndex = analysis.length;
      }
      
      final content = analysis.substring(match.end, endIndex).trim();
      sections.add(AnalysisSection(title, content));
      
      lastEnd = endIndex;
    }
    
    return sections;
  }

  Widget _buildVideoMetricBadge(IconData icon, String count) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 12,
            color: isDark ? Colors.white70 : Colors.grey[700],
          ),
          const SizedBox(width: 4),
          Text(
            count,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildStatsSection(String dataType) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final data = _statsData[dataType] ?? <String, double>{};
    // Ottieni le piattaforme selezionate
    final selectedPlatforms = _getSelectedPlatforms();
    // Mostra solo le chiavi effettive presenti nei dati e tra le piattaforme selezionate
    final filteredData = <String, double>{};
    // Per IG, FB, Threads: mostra sempre l'account, usa manual_views/likes/comments se presente, altrimenti 0
    data.forEach((k, v) {
      String platform = '';
      if (k.startsWith('tiktok')) platform = 'tiktok';
      else if (k.startsWith('twitter')) platform = 'twitter';
      else if (k.startsWith('youtube')) platform = 'youtube';
      else if (k.startsWith('instagram')) platform = 'instagram';
      else if (k.startsWith('facebook')) platform = 'facebook';
      else if (k.startsWith('threads')) platform = 'threads';
      final meta = _accountMeta[k] ?? {};
      final isIGNoToken = platform == 'instagram' && (meta['missing_token'] == true);
      if (platform.isNotEmpty && selectedPlatforms.contains(platform)) {
        if (isIGNoToken) {
          if (dataType == 'views') {
            filteredData[k] = _manualViews[k]?.toDouble() ?? 0;
          } else if (dataType == 'likes') {
            filteredData[k] = _manualLikes[k]?.toDouble() ?? 0;
          } else if (dataType == 'comments') {
            filteredData[k] = _manualComments[k]?.toDouble() ?? 0;
          }
        } else if (dataType == 'views' && (platform == 'instagram' || platform == 'facebook' || platform == 'threads')) {
          if (_manualViews[k] != null) {
            filteredData[k] = _manualViews[k]!.toDouble();
          } else {
            filteredData[k] = 0;
          }
        } else {
      filteredData[k] = v;
        }
      }
    });
    // Mostra anche account IG/FB/Threads che hanno solo manual_views/likes/comments ma non sono in data
    if (dataType == 'views') {
      _manualViews.forEach((k, v) {
        String platform = '';
        if (k.startsWith('instagram')) platform = 'instagram';
        else if (k.startsWith('facebook')) platform = 'facebook';
        else if (k.startsWith('threads')) platform = 'threads';
        if (platform.isNotEmpty && selectedPlatforms.contains(platform)) {
          if (!filteredData.containsKey(k)) {
            filteredData[k] = v.toDouble();
          }
        }
      });
    }
    if (dataType == 'likes') {
      _manualLikes.forEach((k, v) {
        String platform = '';
        if (k.startsWith('instagram')) platform = 'instagram';
        if (platform.isNotEmpty && selectedPlatforms.contains(platform)) {
          final meta = _accountMeta[k] ?? {};
          final isIGNoToken = platform == 'instagram' && (meta['missing_token'] == true);
          if (isIGNoToken && !filteredData.containsKey(k)) {
            filteredData[k] = v.toDouble();
          }
        }
      });
    }
    if (dataType == 'comments') {
      _manualComments.forEach((k, v) {
        String platform = '';
        if (k.startsWith('instagram')) platform = 'instagram';
        if (platform.isNotEmpty && selectedPlatforms.contains(platform)) {
          final meta = _accountMeta[k] ?? {};
          final isIGNoToken = platform == 'instagram' && (meta['missing_token'] == true);
          if (isIGNoToken && !filteredData.containsKey(k)) {
            filteredData[k] = v.toDouble();
          }
        }
      });
    }
    // Get the maximum value for scaling
    final maxValue = filteredData.isEmpty ? 0.0 : filteredData.values.reduce((a, b) => a > b ? a : b);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and info section
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                    'Total: ${_formatNumber(_calculateTotal(filteredData).toInt())}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          // Chart per tutte le sezioni (likes, views, comments)
          if (filteredData.isEmpty)
            Center(
              child: Container(
                height: 320,
                width: 320,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bar_chart_rounded,
                        size: 48,
                        color: isDark ? Colors.white24 : Colors.grey[400],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'No data available',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey[600],
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                height: 320,
                width: (filteredData.length * 90).toDouble().clamp(320, 900), // larghezza dinamica
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxValue > 0 ? maxValue * 1.1 : 100,
                    groupsSpace: 30,
                    barTouchData: BarTouchData(
                      enabled: true,
                      handleBuiltInTouches: true,
                      touchTooltipData: BarTouchTooltipData(
                        tooltipPadding: const EdgeInsets.all(12),
                        tooltipMargin: 8,
                        fitInsideHorizontally: true,
                        fitInsideVertically: true,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final keysList = filteredData.keys.toList();
                          if (groupIndex >= keysList.length) {
                            return BarTooltipItem('', const TextStyle());
                          }
                          String label = _accountMeta[keysList[groupIndex]]?['display_name'] ?? keysList[groupIndex];
                          return BarTooltipItem(
                            '$label\n${_formatNumber(rod.toY.round())}',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          );
                        },
                      ),
                      touchCallback: (FlTouchEvent event, BarTouchResponse? touchResponse) {
                        if (event is FlTapUpEvent && touchResponse != null && touchResponse.spot != null) {
                          final spotIndex = touchResponse.spot!.touchedBarGroupIndex;
                          final keysList = filteredData.keys.toList();
                          if (spotIndex < keysList.length) {
                            final accountKey = keysList[spotIndex];
                            _showPlatformDetails(accountKey, dataType);
                          }
                        }
                        if (event is FlTapDownEvent) {
                          HapticFeedback.lightImpact();
                        }
                      },
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            if (value % 1 != 0 || value < 0 || value >= filteredData.length) {
                              return const SizedBox.shrink();
                            }
                            final keysList = filteredData.keys.toList();
                            if (value.toInt() >= keysList.length) {
                              return const SizedBox.shrink();
                            }
                            final accountKey = keysList[value.toInt()];
                            final metaData = _accountMeta[accountKey] ?? {};
                            final profileImageUrl = metaData['profile_image_url'] as String?;
                            return SideTitleWidget(
                              meta: meta,
                              space: 4,
                              child: GestureDetector(
                                onTap: () {
                                  _showPlatformDetails(accountKey, dataType);
                                },
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: Colors.white,
                                        backgroundImage: (profileImageUrl != null && profileImageUrl.isNotEmpty)
                                            ? NetworkImage(profileImageUrl)
                                            : null,
                                        child: (profileImageUrl == null || profileImageUrl.isEmpty)
                                            ? Icon(Icons.person, size: 20, color: Colors.grey)
                                            : null,
                                      ),
                                      // Mostra sempre l'icona di attenzione per IG, FB, Threads SOLO nella sezione views
                                      if (dataType == 'views' &&
                                          (metaData['platform'] == 'instagram' || metaData['platform'] == 'facebook' || metaData['platform'] == 'threads'))
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Icon(Icons.warning, color: Colors.orange, size: 14),
                                        ),
                                      // Altrimenti mostra solo se manca il token (per altre sezioni o piattaforme)
                                      if (dataType != 'views' && metaData['missing_token'] == true)
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Icon(Icons.warning, color: Colors.orange, size: 14),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          reservedSize: 28,
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) {
                            return SideTitleWidget(
                              meta: meta,
                              space: 4,
                              child: Text(
                                _formatCompactNumber(value),
                                style: const TextStyle(
                                  color: Color(0xFF7F7F7F),
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(
                      show: false,
                    ),
                    barGroups: _buildFilteredBarGroups(filteredData),
                    gridData: FlGridData(
                      show: false,
                    ),
                  ),
                ),
              ),
            ),
          // Summary section: Top Platforms
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                  ),
                ),
                    const SizedBox(width: 8),
                Text(
                      'Top Platforms',
                  style: TextStyle(
                    fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1F1F1F),
                  ),
                ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildSummaryRow(dataType, filteredData),
              ],
            ),
          ),
          // Top Account Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Top Accounts',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1F1F1F),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ..._buildTopAccountsList(filteredData, theme, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Top 3 account con valore maggiore per la metrica selezionata
  List<Widget> _buildTopAccountsList(Map<String, double> filteredData, ThemeData theme, bool isDark) {
    // Ordina tutti gli account per valore decrescente
    final sortedAccounts = filteredData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topAccounts = sortedAccounts.take(3).toList();
    if (topAccounts.isEmpty) {
      return [
        Center(
          child: Text(
            'No account data available',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.grey[600],
              fontSize: 16,
            ),
          ),
        )
      ];
    }
    return List.generate(topAccounts.length, (index) {
      final entry = topAccounts[index];
      final accountKey = entry.key;
      final value = entry.value;
      final metaData = _accountMeta[accountKey] ?? {};
      final profileImageUrl = metaData['profile_image_url'] as String?;
      final displayName = metaData['display_name'] as String?;
      final platform = metaData['platform'] as String? ?? accountKey.replaceAll(RegExp(r'\d'), '');
      Color color;
      if (platform == 'youtube') {
        color = const Color(0xFFFF0000);
      } else if (platform == 'instagram') {
        color = const Color(0xFFE1306C);
      } else if (platform == 'facebook') {
        color = const Color(0xFF1877F2);
      } else if (platform == 'threads') {
        color = const Color(0xFF101010);
      } else {
        color = theme.colorScheme.primary;
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: profileImageUrl != null && profileImageUrl.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        profileImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(Icons.person, size: 22, color: Colors.grey),
                      ),
                    )
                  : Icon(Icons.person, size: 22, color: Colors.grey),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName ?? accountKey,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.grey[900],
                    ),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: topAccounts.first.value > 0 ? value / topAccounts.first.value : 0,
                    backgroundColor: color.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatNumber(value.toInt()),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.grey[800],
                  ),
                ),
                Text(
                  platform[0].toUpperCase() + platform.substring(1),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  // Format numbers with commas
  String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
  
  // Format compact numbers (1K, 1M, etc)
  String _formatCompactNumber(double number) {
    final abs = number.abs();
    final sign = number < 0 ? '-' : '';

    if (abs < 1000) {
      return '${sign}${abs.toInt()}';
    }

    // 1,000 - 9,999 -> one decimal K (e.g., 2.3K), trim trailing .0
    if (abs < 10000) {
      final val = abs / 1000.0;
      String s = val.toStringAsFixed(1);
      if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
      return '${sign}${s}K';
    }

    // 10,000 - 999,999 -> integer K (e.g., 11K, 200K)
    if (abs < 1000000) {
      final k = abs ~/ 1000;
      return '${sign}${k}K';
    }

    // 1,000,000 - 9,999,999 -> one decimal M, trim trailing .0
    if (abs < 10000000) {
      final val = abs / 1000000.0;
      String s = val.toStringAsFixed(1);
      if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
      return '${sign}${s}M';
    }

    // 10,000,000+ -> integer M (e.g., 10M, 150M)
    final m = abs ~/ 1000000;
    return '${sign}${m}M';
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
  Widget _buildSummaryRow(String dataType, Map<String, double> filteredData) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Aggrega i valori per piattaforma (somma tutti gli account per ogni piattaforma)
    final Map<String, double> platformTotals = {};
    final Map<String, String> platformIcons = {
      'youtube': 'assets/loghi/logo_yt.png',
      'instagram': 'assets/loghi/logo_insta.png',
      'facebook': 'assets/loghi/logo_facebook.png',
      'threads': 'assets/loghi/threads_logo.png',
      'tiktok': 'assets/loghi/logo_tiktok.png',
      'twitter': 'assets/loghi/logo_twitter.png',
    };
    filteredData.forEach((accountKey, value) {
      String platform = '';
      if (accountKey.startsWith('youtube')) platform = 'youtube';
      else if (accountKey.startsWith('instagram')) platform = 'instagram';
      else if (accountKey.startsWith('facebook')) platform = 'facebook';
      else if (accountKey.startsWith('threads')) platform = 'threads';
      else if (accountKey.startsWith('tiktok')) platform = 'tiktok';
      else if (accountKey.startsWith('twitter')) platform = 'twitter';
      if (platform.isNotEmpty) {
        platformTotals[platform] = (platformTotals[platform] ?? 0) + value;
      }
    });
    final total = platformTotals.values.isEmpty ? 0 : platformTotals.values.reduce((a, b) => a + b);
    // Ordina le piattaforme per valore decrescente
    final sortedPlatforms = platformTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topPlatforms = sortedPlatforms.take(2).toList();
    if (topPlatforms.isEmpty) {
      return Center(
        child: Text(
          'No data available',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.grey[600],
            fontSize: 16,
          ),
        ),
      );
    }
    return Column(
      children: [
        ...List.generate(
          topPlatforms.length,
          (index) {
            final entry = topPlatforms[index];
            final platform = entry.key;
            final value = entry.value;
            final percentage = total > 0 ? (value / total * 100) : 0;
            final iconPath = platformIcons[platform];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Icona piattaforma
                      if (iconPath != null)
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              iconPath,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Icon(Icons.person, size: 18, color: Colors.grey),
                            ),
                          ),
                        ),
                      const SizedBox(width: 12),
                      // Nome piattaforma
                      Text(
                        platform[0].toUpperCase() + platform.substring(1),
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.grey[800],
                        ),
                      ),
                      const Spacer(),
                      // Value and percentage
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatNumber(value.toInt()),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.grey[800],
                            ),
                          ),
                          Text(
                            '(${percentage.toStringAsFixed(1)}%)',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: topPlatforms.first.value > 0 ? value / topPlatforms.first.value : 0,
                      backgroundColor: isDark 
                          ? Colors.grey.withOpacity(0.1) 
                          : Colors.grey.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        platform == 'youtube' ? const Color(0xFFFF0000)
                        : platform == 'instagram' ? const Color(0xFFE1306C)
                        : platform == 'facebook' ? const Color(0xFF1877F2)
                        : platform == 'threads' ? const Color(0xFF101010)
                        : Colors.grey,
                      ),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  String _getPlatformLogoAsset(String platform) {
    switch (platform) {
      case 'tiktok':
        return 'assets/loghi/logo_tiktok.png';
      case 'youtube':
        return 'assets/loghi/logo_yt.png';
      case 'instagram':
        return 'assets/loghi/logo_insta.png';
      case 'threads':
        return 'assets/loghi/threads_logo.png';
      case 'facebook':
        return 'assets/loghi/logo_facebook.png';
      case 'twitter':
        return 'assets/loghi/logo_twitter.png';
      default:
        return 'assets/loghi/logo_tiktok.png';
    }
  }

  String _getPlatformShortName(String platform) {
    switch (platform) {
      case 'tiktok':
        return 'TT';
      case 'youtube':
        return 'YT';
      case 'instagram':
        return 'IG';
      case 'threads':
        return 'TH';
      case 'facebook':
        return 'FB';
      case 'twitter':
        return 'TW';
      default:
        return '';
    }
  }
  
  String _getPlatformFullName(String platform) {
    switch (platform) {
      case 'tiktok':
        return 'TikTok';
      case 'youtube':
        return 'YouTube';
      case 'instagram':
        return 'Instagram';
      case 'threads':
        return 'Threads';
      case 'facebook':
        return 'Facebook';
      case 'twitter':
        return 'Twitter';
      default:
        return '';
    }
  }
  void _showInfoDialog(String dataType) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    String title;
    String content;
    IconData icon;
    
    switch (dataType) {
      case 'likes':
        title = 'About Like Statistics';
        content = 'This chart shows the number of likes your video has received across different social media platforms. Likes are a key engagement metric that indicates how well your content resonates with audiences.';
        icon = Icons.thumb_up_outlined;
        break;
      case 'views':
        title = 'About View Statistics';
        content = 'This chart shows the number of views your video has received across different social media platforms. Views represent the reach of your content and how many people have watched it.';
        icon = Icons.visibility_outlined;
        break;
      case 'comments':
        title = 'About Comment Statistics';
        content = 'This chart shows the number of comments your video has received across different social media platforms. Comments indicate deeper engagement and audience interaction with your content.';
        icon = Icons.chat_bubble_outline;
        break;
      default:
        title = 'Information';
        content = 'Statistics information for your video content.';
        icon = Icons.info_outline;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              icon,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[800],
              ),
            ),
          ],
        ),
        content: Text(
          content,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.grey[700],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPlatformDetails(String accountKey, String dataType) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final metaData = _accountMeta[accountKey] ?? {};
    final profileImageUrl = metaData['profile_image_url'] as String?;
    final displayName = metaData['display_name'] as String?;
    final platform = metaData['platform'] as String? ?? accountKey.replaceAll(RegExp(r'\d'), '');
    final bool isInstagramMissingToken = platform == 'instagram' && metaData['missing_token'] == true;
    final bool isManualViewsPlatform = platform == 'instagram' || platform == 'facebook' || platform == 'threads';
    final TextEditingController manualViewsController = TextEditingController(
      text: _manualViews[accountKey]?.toString() ?? (_statsData['views']?[accountKey]?.toInt().toString() ?? ''),
    );
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          snap: true,
          snapSizes: const [0.7, 0.95],
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: (platform != null && _platformColors.containsKey(platform)) ? _platformColors[platform]!.withOpacity(0.1) : Colors.grey[200],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: profileImageUrl != null && profileImageUrl.isNotEmpty
                              ? ClipOval(
                                  child: Image.network(
                                    profileImageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Icon(Icons.person, size: 24, color: Colors.grey),
                                  ),
                                )
                              : Icon(Icons.person, size: 24, color: Colors.grey),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          displayName ?? accountKey,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (isInstagramMissingToken) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[900] : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.withOpacity(0.15)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Instagram Analytics Access',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'To view analytics and insights for this Instagram account, you need to complete advanced access. Proceed ONLY if your Instagram account is linked to a Facebook page.',
                                  style: TextStyle(
                                    color: isDark ? Colors.white70 : Colors.grey[800],
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.withOpacity(0.2)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'You can continue publishing with basic access, and add manual data',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.w500,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.grey[900] : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.withOpacity(0.15)),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Proceed ONLY if your Instagram account is linked to a Facebook page',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.w500,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          // --- BOTTONE PER ACCESSO INSTAGRAM DIRETTO (spostato qui) ---
                          Center(
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: Icon(Icons.lock_open, color: Colors.white),
                                label: Text('Complete Instagram access', style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (context) => InstagramPage(autoConnect: true, autoConnectType: 'basic'),
                                  ));
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          // --- CAMPI MANUALI: views, likes, comments ---
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                _ManualStatRow(
                                  accountKey: accountKey,
                                  value: _manualViews[accountKey] ?? _statsData['views']?[accountKey]?.toInt() ?? 0,
                                  onValueChanged: (val) {
                                    setState(() {
                                      _manualViews[accountKey] = val;
                                      _statsData['views']?[accountKey] = val.toDouble();
                                    });
                                  },
                                  videoId: widget.video['id']?.toString() ?? widget.video['key']?.toString() ?? '',
                                  socialmedia: metaData['platform'] ?? '',
                                  username: metaData['account_username'] ?? metaData['username'] ?? '',
                                  displayName: metaData['display_name'] ?? '',
                                  uid: FirebaseAuth.instance.currentUser?.uid ?? '',
                                  label: 'Views',
                                  firebaseKey: 'manual_views',
                                ),
                                const Divider(height: 24),
                                _ManualStatRow(
                                  accountKey: accountKey,
                                  value: (_manualLikes[accountKey] ?? _statsData['likes']?[accountKey]?.toInt() ?? 0),
                                  onValueChanged: (val) {
                                    setState(() {
                                      _manualLikes[accountKey] = val;
                                      _statsData['likes']?[accountKey] = val.toDouble();
                                    });
                                  },
                                  videoId: widget.video['id']?.toString() ?? widget.video['key']?.toString() ?? '',
                                  socialmedia: metaData['platform'] ?? '',
                                  username: metaData['account_username'] ?? metaData['username'] ?? '',
                                  displayName: metaData['display_name'] ?? '',
                                  uid: FirebaseAuth.instance.currentUser?.uid ?? '',
                                  label: 'Likes',
                                  firebaseKey: 'manual_likes',
                                ),
                                const Divider(height: 24),
                                _ManualStatRow(
                                  accountKey: accountKey,
                                  value: (_manualComments[accountKey] ?? _statsData['comments']?[accountKey]?.toInt() ?? 0),
                                  onValueChanged: (val) {
                                    setState(() {
                                      _manualComments[accountKey] = val;
                                      _statsData['comments']?[accountKey] = val.toDouble();
                                    });
                                  },
                                  videoId: widget.video['id']?.toString() ?? widget.video['key']?.toString() ?? '',
                                  socialmedia: metaData['platform'] ?? '',
                                  username: metaData['account_username'] ?? metaData['username'] ?? '',
                                  displayName: metaData['display_name'] ?? '',
                                  uid: FirebaseAuth.instance.currentUser?.uid ?? '',
                                  label: 'Comments',
                                  firebaseKey: 'manual_comments',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Performance Metrics',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.grey[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildPerformanceMetricCard(
                            'Engagement Rate',
                            '${_calculateEngagementRate(accountKey).toStringAsFixed(2)}%',
                            Icons.trending_up,
                            Colors.green,
                          ),
                          const SizedBox(height: 12),
                          _buildPerformanceMetricCard(
                            'Like Rate',
                            '${_calculateLikeRate(accountKey).toStringAsFixed(2)}%',
                            Icons.thumb_up_outlined,
                            Colors.blue,
                          ),
                          const SizedBox(height: 12),
                          _buildPerformanceMetricCard(
                            'Comment Rate',
                            '${_calculateCommentRate(accountKey).toStringAsFixed(2)}%',
                            Icons.chat_bubble_outline,
                            Colors.purple,
                          ),
                        ],
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            _buildPlatformStatRow('Likes', _getLikesForMetrics(accountKey).toInt()),
                            const Divider(height: 24),
                            // Campo input manuale per views SOLO per IG, FB, Threads
                            if (isManualViewsPlatform)
                              _ManualViewsRow(
                                accountKey: accountKey,
                                value: _manualViews[accountKey] ?? _statsData['views']?[accountKey]?.toInt() ?? 0,
                                onValueChanged: (val) {
                                  setState(() {
                                    _manualViews[accountKey] = val;
                                    _statsData['views']?[accountKey] = val.toDouble();
                                  });
                                },
                                videoId: widget.video['id']?.toString() ?? widget.video['key']?.toString() ?? '',
                                socialmedia: metaData['platform'] ?? '',
                                username: metaData['account_username'] ?? metaData['username'] ?? '',
                                displayName: metaData['display_name'] ?? '',
                                uid: FirebaseAuth.instance.currentUser?.uid ?? '',
                              )
                            else
                            _buildPlatformStatRow('Views', _statsData['views']?[accountKey]?.toInt() ?? 0),
                            const Divider(height: 24),
                            _buildPlatformStatRow('Comments', _getCommentsForMetrics(accountKey).toInt()),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 16,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Performance Metrics',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildPerformanceMetricCard(
                        'Engagement Rate',
                        '${_calculateEngagementRate(accountKey).toStringAsFixed(2)}%',
                        Icons.trending_up,
                        Colors.green,
                      ),
                      const SizedBox(height: 12),
                      _buildPerformanceMetricCard(
                        'Like Rate',
                        '${_calculateLikeRate(accountKey).toStringAsFixed(2)}%',
                        Icons.thumb_up_outlined,
                        Colors.blue,
                      ),
                      const SizedBox(height: 12),
                      _buildPerformanceMetricCard(
                        'Comment Rate',
                        '${_calculateCommentRate(accountKey).toStringAsFixed(2)}%',
                        Icons.chat_bubble_outline,
                        Colors.purple,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.analytics_outlined, color: Colors.white),
                          label: Text('View Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _platformColors[platform] ?? Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            _openPostUrl(platform);
                          },
                        ),
                      ),
                      // --- AVVISO LIMITAZIONE META (solo IG senza token, Facebook, Threads) ---
                      if ((platform == 'instagram' && isInstagramMissingToken) || platform == 'facebook' || platform == 'threads')
                        Padding(
                          padding: const EdgeInsets.only(top: 24.0, left: 4, right: 4, bottom: 8),
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outline.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 22,
                                  color: theme.brightness == Brightness.dark ? Color(0xFF6C63FF) : theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Due to Meta platform limitations, it is not possible to retrieve the number of views directly. For more detailed analytics, use the button above to open the official dashboard. You can also add views manually below for better AI analysis.',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlatformStatRow(String label, int value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: isDark ? Colors.white70 : Colors.grey[700],
          ),
        ),
        Text(
          _formatNumber(value),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceMetricCard(String label, String value, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Calcola la somma totale dei valori di una mappa
  double _calculateTotal(Map<String, double> data) {
    if (data.isEmpty) return 0;
    return data.values.reduce((a, b) => a + b);
  }

  // Metodi helper per calcolare le metriche in modo sicuro
  double _calculateEngagementRate(String accountKey) {
    final likes = _statsData['likes']?[accountKey] ?? 0;
    final comments = _statsData['comments']?[accountKey] ?? 0;
    final views = _getViewsForMetrics(accountKey);
    if (views == 0) return 0;
    return ((likes + comments) / views) * 100;
  }

  double _calculateLikeRate(String accountKey) {
    final likes = _statsData['likes']?[accountKey] ?? 0;
    final views = _getViewsForMetrics(accountKey);
    if (views == 0) return 0;
    return (likes / views) * 100;
  }

  double _calculateCommentRate(String accountKey) {
    final comments = _statsData['comments']?[accountKey] ?? 0;
    final views = _getViewsForMetrics(accountKey);
    if (views == 0) return 0;
    return (comments / views) * 100;
  }

  // Ottiene le piattaforme selezionate per questo video dal database Firebase
  Set<String> _getSelectedPlatforms() {
    final dynamic raw = widget.video['platforms'];
    if (raw != null) {
      final List<String> platforms = <String>[];
      if (raw is List) {
        for (final item in raw) {
          if (item != null) platforms.add(item.toString());
        }
      } else if (raw is Map) {
        for (final value in (raw as Map).values) {
          if (value != null) platforms.add(value.toString());
        }
      } else if (raw is String) {
        platforms.add(raw);
      }
      if (platforms.isNotEmpty) {
        final selectedPlatforms = platforms.map((platform) => platform.toLowerCase()).toSet();
        return selectedPlatforms;
      }
    }
    // Se non disponibile localmente, prova a recuperare dal database Firebase
    _loadPlatformsFromFirebase();
    // Per ora restituisci un set vuoto, verrà aggiornato quando i dati arrivano
    return <String>{};
  }

  // Recupera le piattaforme dal database Firebase e aggiorna lo stato
  Future<void> _loadPlatformsFromFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }
      
      final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
      if (videoId == null) {
        return;
      }
      
      
      
      final databaseRef = FirebaseDatabase.instance.ref();
      // Usa l'user_id del video (nuovo formato) se presente, altrimenti fallback all'utente corrente
      final videoOwnerId = widget.video['user_id']?.toString() ?? user.uid;
      final videoRef = databaseRef.child('users').child('users').child(videoOwnerId).child('videos').child(videoId);
        final snapshot = await videoRef.child('platforms').get();
        
        if (snapshot.exists) {
          final dynamic raw = snapshot.value;
          final List<String> platforms = <String>[];
          if (raw is List) {
            for (final item in raw) {
              if (item != null) platforms.add(item.toString());
            }
          } else if (raw is Map) {
            // iOS Firebase can return maps for arrays; collect values
            for (final value in (raw as Map).values) {
              if (value != null) platforms.add(value.toString());
            }
          } else if (raw is String) {
            platforms.add(raw);
          }
          if (platforms.isNotEmpty) {
            widget.video['platforms'] = platforms;
            if (mounted) setState(() {});
          } else {
          // Fallback: deduci le piattaforme dal nuovo formato (accounts in sottocartelle)
          try {
            final accountsRef = videoRef.child('accounts');
            final List<String> detected = [];
            final List<String> platformNames = ['Facebook', 'Instagram', 'YouTube', 'Threads', 'TikTok', 'Twitter'];
            for (final name in platformNames) {
              final accSnap = await accountsRef.child(name).get();
              if (accSnap.exists) {
                final val = accSnap.value;
                bool hasContent = false;
                if (val is List) {
                  hasContent = val.isNotEmpty;
                } else if (val is Map) {
                  hasContent = val.isNotEmpty;
                } else if (val != null) {
                  hasContent = true;
                }
                if (hasContent) detected.add(name.toLowerCase());
              }
            }
            // Considera anche gli ID a livello video come ulteriore segnale
            void addIfIdPresent(String key) {
              final v = widget.video['${key}_id']?.toString();
              if (v != null && v.isNotEmpty && !detected.contains(key)) detected.add(key);
            }
            addIfIdPresent('tiktok');
            addIfIdPresent('youtube');
            addIfIdPresent('instagram');
            addIfIdPresent('threads');
            addIfIdPresent('facebook');
            addIfIdPresent('twitter');
            if (detected.isNotEmpty) {
              widget.video['platforms'] = detected;
              if (mounted) setState(() {});
            }
          } catch (_) {}
          }
        } else {
        // Nessuna lista piattaforme salvata: prova a dedurre dal nuovo formato
        try {
          final accountsRef = videoRef.child('accounts');
          final List<String> detected = [];
          final List<String> platformNames = ['Facebook', 'Instagram', 'YouTube', 'Threads', 'TikTok', 'Twitter'];
          for (final name in platformNames) {
            final accSnap = await accountsRef.child(name).get();
            if (accSnap.exists) {
              final val = accSnap.value;
              bool hasContent = false;
              if (val is List) {
                hasContent = val.isNotEmpty;
              } else if (val is Map) {
                hasContent = val.isNotEmpty;
              } else if (val != null) {
                hasContent = true;
              }
              if (hasContent) detected.add(name.toLowerCase());
            }
          }
          void addIfIdPresent(String key) {
            final v = widget.video['${key}_id']?.toString();
            if (v != null && v.isNotEmpty && !detected.contains(key)) detected.add(key);
          }
          addIfIdPresent('tiktok');
          addIfIdPresent('youtube');
          addIfIdPresent('instagram');
          addIfIdPresent('threads');
          addIfIdPresent('facebook');
          addIfIdPresent('twitter');
          if (detected.isNotEmpty) {
            widget.video['platforms'] = detected;
            if (mounted) setState(() {});
          }
        } catch (_) {}
        
        // Controlla se il video esiste (no-op, solo per compatibilità con la logica precedente)
        final videoSnapshot = await videoRef.get();
        if (videoSnapshot.exists) {
        } else {
        }
      }
    } catch (e) {
      
    }
  }

  // Costruisce i bar groups filtrati per le piattaforme selezionate
  List<BarChartGroupData> _buildFilteredBarGroups(Map<String, double> filteredData) {
    final List<BarChartGroupData> barGroups = [];
    int index = 0;
    
    // Aggiungi solo le piattaforme che hanno dati
    for (final entry in filteredData.entries) {
      final platform = entry.key;
      final value = entry.value;
      // Determina il colore in base al prefisso della chiave account
      Color color;
      if (platform.startsWith('youtube')) {
        color = const Color(0xFFFF0000); // Rosso YouTube
      } else if (platform.startsWith('instagram')) {
        color = const Color(0xFFE1306C); // Viola/rosa Instagram
      } else if (platform.startsWith('facebook')) {
        color = const Color(0xFF1877F2); // Celeste Facebook
      } else if (platform.startsWith('threads')) {
        color = const Color(0xFF101010); // Nero Threads
      } else {
        color = _platformColors[platform] ?? Colors.grey;
      }
      
      barGroups.add(_buildBarGroup(index, value, color));
      index++;
    }
    
    return barGroups;
  }
  // Funzione per aprire l'URL del post
  Future<void> _openPostUrl(String platform) async {
    String? url;
    
    // Debug log - inizio
    print('DEBUG: Apertura URL per piattaforma: $platform');
    
    // Ottieni l'ID utente dal video
    final userId = widget.video['user_id']?.toString() ?? '';
    print('DEBUG: User ID: $userId');
    
    if (userId.isEmpty) {
      print('DEBUG: User ID non disponibile nel video');
      _mostraErrore('Impossibile identificare l\'utente per questo video');
      return;
    }
    
    try {
      // Riferimento al database Firebase
      final databaseRef = FirebaseDatabase.instance.ref();
      print('DEBUG: Tentativo di accesso a Firebase Database');
      
      // Estrai gli ID dei post dal video
      final tikTokId = widget.video['tiktok_id']?.toString() ?? '';
      final youtubeId = widget.video['youtube_id']?.toString() ?? '';
      final instagramId = widget.video['instagram_id']?.toString() ?? '';
      final threadsId = widget.video['threads_id']?.toString() ?? '';
      final facebookId = widget.video['facebook_id']?.toString() ?? '';
      String twitterId = widget.video['twitter_id']?.toString() ?? ''; // Non più final per poterlo modificare
      
      // Debug log - IDs dal video
      print('DEBUG: IDs dal video - TikTok: $tikTokId, YouTube: $youtubeId, Instagram: $instagramId');
      print('DEBUG: IDs dal video - Threads: $threadsId, Facebook: $facebookId, Twitter: $twitterId');
      
      // Recupera i dati dell'utente da Firebase (nuovo formato -> fallback al vecchio)
      DataSnapshot userSnapshot = await databaseRef.child('users').child('users').child(userId).get();
      if (!userSnapshot.exists) {
        userSnapshot = await databaseRef.child('users').child(userId).get();
      }
      if (!userSnapshot.exists) {
        print('DEBUG: Utente non trovato in Firebase');
        _mostraErrore('Dati utente non disponibili');
        return;
      }
      
      final userData = userSnapshot.value as Map<dynamic, dynamic>;
      print('DEBUG: Dati utente recuperati da Firebase');
      
      // Variabili per memorizzare gli ID e username necessari
      String? twitterUsername;
      String? instagramBusinessId;
      String? instagramContentId;
      String? facebookContentInsightsId;
      String? youtubeChannelId;
      String? tiktokOpenId;
      
      // Recupera i dati degli account social
      switch (platform.toLowerCase()) {
        case 'tiktok':
          if (userData.containsKey('tiktok') && userData['tiktok'] is Map) {
            final tiktokAccounts = userData['tiktok'] as Map<dynamic, dynamic>;
            if (tiktokAccounts.isNotEmpty) {
              // Prendi il primo account TikTok disponibile
              final firstAccount = tiktokAccounts.entries.first;
              tiktokOpenId = firstAccount.key.toString();
              print('DEBUG: TikTok open_id trovato: $tiktokOpenId');
              
              if (tikTokId.isNotEmpty) {
                url = 'https://www.tiktok.com/tiktokstudio/analytics/$tikTokId';
                print('DEBUG: URL TikTok costruito con video ID: $url');
              } else {
                url = 'https://www.tiktok.com/tiktokstudio/analytics';
                print('DEBUG: URL TikTok generico: $url');
              }
            }
          } else {
            print('DEBUG: Nessun account TikTok trovato');
            url = 'https://www.tiktok.com/creator-center/analytics';
          }
          break;
          
        case 'youtube':
          // Per YouTube, recupera il post_id dal video specifico e costruisci l'URL corretto
          try {
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null) {
              final db = FirebaseDatabase.instance.ref();
              final videoId = widget.video['id']?.toString();
              final userId = widget.video['user_id']?.toString();
              
              if (videoId != null && userId != null) {
                // Controlla se è formato nuovo
                final isNewFormat = videoId.contains(userId);
                
                String? postId;
                String? accountId;
                
                if (isNewFormat) {
                  // --- FORMATO NUOVO: users/users/[uid]/videos/[idvideo]/accounts/YouTube/ ---
                  final videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('YouTube');
                  final videoAccountsSnap = await videoAccountsRef.get();
                  if (videoAccountsSnap.exists) {
                    final videoAccounts = videoAccountsSnap.value;
                    
                    if (videoAccounts is Map) {
                      // Caso: un solo account per piattaforma (oggetto diretto)
                      postId = videoAccounts['post_id']?.toString() ?? videoAccounts['youtube_video_id']?.toString();
                      accountId = videoAccounts['account_id']?.toString();
                    } else if (videoAccounts is List) {
                      // Caso: più account per piattaforma (lista di oggetti)
                      for (final accountData in videoAccounts) {
                        if (accountData is Map) {
                          postId = accountData['post_id']?.toString() ?? accountData['youtube_video_id']?.toString();
                          accountId = accountData['account_id']?.toString();
                          break; // Prendi il primo
                        }
                      }
                    }
                  }
                } else {
                  // --- FORMATO VECCHIO: users/users/[uid]/videos/[idvideo]/accounts/YouTube/[numero]/ ---
                  final videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('YouTube');
                  final videoAccountsSnap = await videoAccountsRef.get();
                  if (videoAccountsSnap.exists) {
                    final videoAccounts = videoAccountsSnap.value as List<dynamic>;
                    
                    if (videoAccounts.isNotEmpty) {
                      final accountData = videoAccounts.first as Map<dynamic, dynamic>;
                      postId = accountData['post_id']?.toString() ?? accountData['youtube_video_id']?.toString();
                      accountId = accountData['id']?.toString();
                    }
                  }
                }
                
                if (postId != null && postId.isNotEmpty) {
                  // Costruisci URL per analytics specifici del video
                  url = 'https://studio.youtube.com/video/$postId/analytics/tab-overview/period-default';
                  print('[YOUTUBE] URL analytics costruito per video specifico: $url');
                } else {
                  // Se non abbiamo il post_id, usa l'URL generico del canale
          if (userData.containsKey('youtube') && userData['youtube'] is Map) {
            final youtubeAccounts = userData['youtube'] as Map<dynamic, dynamic>;
            if (youtubeAccounts.isNotEmpty) {
              final firstAccount = youtubeAccounts.entries.first;
                      final channelId = firstAccount.key.toString();
                      url = 'https://studio.youtube.com/channel/$channelId/analytics';
                      print('[YOUTUBE] URL analytics generico del canale: $url');
              } else {
                      url = 'https://studio.youtube.com/channel/analytics';
                      print('[YOUTUBE] URL analytics generico: $url');
                    }
                  } else {
                    url = 'https://studio.youtube.com/channel/analytics';
                    print('[YOUTUBE] URL analytics generico: $url');
              }
            }
          } else {
                print('[YOUTUBE] Video ID o User ID mancanti');
                url = 'https://studio.youtube.com/channel/analytics';
              }
            } else {
              print('[YOUTUBE] Nessun utente autenticato');
              url = 'https://studio.youtube.com/channel/analytics';
            }
          } catch (e) {
            print('[YOUTUBE] Errore durante il fetch del post_id: $e');
            url = 'https://studio.youtube.com/channel/analytics';
          }
          break;
          
        case 'instagram':
          // Per Instagram, recupera il media_id dal video specifico e costruisci l'URL corretto
          try {
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null) {
              final db = FirebaseDatabase.instance.ref();
              final videoId = widget.video['id']?.toString();
              final userId = widget.video['user_id']?.toString();
              
              if (videoId != null && userId != null) {
                // Controlla se è formato nuovo
                final isNewFormat = videoId.contains(userId);
                
                String? mediaId;
                String? accountId;
                
                if (isNewFormat) {
                  // --- FORMATO NUOVO: users/users/[uid]/videos/[idvideo]/accounts/Instagram/ ---
                  final videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Instagram');
                  final videoAccountsSnap = await videoAccountsRef.get();
                  if (videoAccountsSnap.exists) {
                    final videoAccounts = videoAccountsSnap.value;
                    
                    if (videoAccounts is Map) {
                      // Caso: un solo account per piattaforma (oggetto diretto)
                      mediaId = videoAccounts['media_id']?.toString();
                      accountId = videoAccounts['account_id']?.toString();
                    } else if (videoAccounts is List) {
                      // Caso: più account per piattaforma (lista di oggetti)
                      for (final accountData in videoAccounts) {
                        if (accountData is Map) {
                          mediaId = accountData['media_id']?.toString();
                          accountId = accountData['account_id']?.toString();
                          break; // Prendi il primo
                        }
                      }
                    }
                  }
                } else {
                  // --- FORMATO VECCHIO: users/users/[uid]/videos/[idvideo]/accounts/Instagram/[numero]/ ---
                  final videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Instagram');
                  final videoAccountsSnap = await videoAccountsRef.get();
                  if (videoAccountsSnap.exists) {
                    final videoAccounts = videoAccountsSnap.value as List<dynamic>;
                    
                    if (videoAccounts.isNotEmpty) {
                      final accountData = videoAccounts.first as Map<dynamic, dynamic>;
                      mediaId = accountData['media_id']?.toString();
                      accountId = accountData['id']?.toString();
                    }
                  }
                }
                
                if (mediaId != null && mediaId.isNotEmpty && accountId != null && accountId.isNotEmpty) {
                  // Verifica se l'account ha il facebook_access_token
                  final instagramAccountSnap = await db.child('users').child(currentUser.uid).child('instagram').child(accountId).get();
                  bool hasFacebookAccessToken = false;
                  if (instagramAccountSnap.exists) {
                    final instagramAccountData = instagramAccountSnap.value as Map<dynamic, dynamic>;
                    hasFacebookAccessToken = instagramAccountData['facebook_access_token'] != null && instagramAccountData['facebook_access_token'].toString().isNotEmpty;
                  }
                  
                  if (hasFacebookAccessToken) {
                    // Account connesso a Facebook - costruisci URL corretto per insights
                    url = 'https://business.facebook.com/latest/insights/object_insights/?content_id=$mediaId&nav_ref=bizweb_insights_uta_table';
                    print('[INSTAGRAM] URL insights costruito per account con Facebook: $url');
              } else {
                    // Account senza Facebook - apri direttamente il profilo Instagram
                    // Recupera l'username dell'account Instagram
                    final instagramAccountSnap = await db.child('users').child(currentUser.uid).child('instagram').child(accountId).get();
                    String? username;
                    if (instagramAccountSnap.exists) {
                      final instagramAccountData = instagramAccountSnap.value as Map<dynamic, dynamic>;
                      username = instagramAccountData['username']?.toString();
                    }
                    
                    if (username != null && username.isNotEmpty) {
                      url = 'https://www.instagram.com/$username/';
                      print('[INSTAGRAM] URL profilo costruito per account senza Facebook: $url');
                    } else {
                      // Fallback se non riusciamo a trovare l'username
                      url = 'https://www.instagram.com/';
                      print('[INSTAGRAM] URL generico Instagram per account senza Facebook: $url');
                    }
                  }
                } else {
                  print('[INSTAGRAM] Nessun media_id o accountId trovato');
                url = 'https://business.facebook.com/latest/insights';
              }
              } else {
                print('[INSTAGRAM] Video ID o User ID mancanti');
                url = 'https://business.facebook.com/latest/insights';
            }
          } else {
              print('[INSTAGRAM] Nessun utente autenticato');
              url = 'https://business.facebook.com/latest/insights';
            }
          } catch (e) {
            print('[INSTAGRAM] Errore durante il fetch del media_id: $e');
            url = 'https://business.facebook.com/latest/insights';
          }
          break;
          
        case 'facebook':
          if (userData.containsKey('facebook') && userData['facebook'] is Map) {
            final facebookAccounts = userData['facebook'] as Map<dynamic, dynamic>;
            if (facebookAccounts.isNotEmpty) {
              // Prendi il primo account Facebook disponibile
              final firstAccount = facebookAccounts.entries.first;
              facebookContentInsightsId = firstAccount.key.toString();
              print('DEBUG: Facebook content_insights_id trovato: $facebookContentInsightsId');
              
              if (facebookId.isNotEmpty && facebookContentInsightsId != null) {
                url = 'https://www.facebook.com/content/insights/?content_id=$facebookContentInsightsId&entry_point=CometProfileInsightsPressablePostListItem';
                print('DEBUG: URL Facebook completo costruito: $url');
              } else {
                url = 'https://www.facebook.com/insights';
                print('DEBUG: URL Facebook generico: $url');
              }
            }
          } else {
            print('DEBUG: Nessun account Facebook trovato');
            url = 'https://www.facebook.com/insights';
          }
          break;
          
        case 'twitter':
          // Cerca prima negli account social dell'utente
          if (userData.containsKey('social_accounts') && 
              userData['social_accounts'] is Map && 
              userData['social_accounts'].containsKey('twitter')) {
            
            final twitterAccounts = userData['social_accounts']['twitter'] as Map<dynamic, dynamic>;
            if (twitterAccounts.isNotEmpty) {
              final firstAccount = twitterAccounts.entries.first;
              final accountData = firstAccount.value as Map<dynamic, dynamic>;
              
              if (accountData.containsKey('username')) {
                twitterUsername = accountData['username'].toString();
              }
            }
          }
          
          // Se non trovato, cerca direttamente nella sezione twitter
          if (twitterUsername == null && userData.containsKey('twitter') && userData['twitter'] is Map) {
            final twitterAccounts = userData['twitter'] as Map<dynamic, dynamic>;
            if (twitterAccounts.isNotEmpty) {
              final firstAccount = twitterAccounts.entries.first;
              final accountData = firstAccount.value as Map<dynamic, dynamic>;
              
              if (accountData.containsKey('username')) {
                twitterUsername = accountData['username'].toString();
              }
            }
          }
          
          // Cerca anche nell'indice degli account social
          if (twitterUsername == null) {
            try {
              final indexSnapshot = await databaseRef.child('social_accounts_index/twitter').get();
              if (indexSnapshot.exists) {
                final indexData = indexSnapshot.value as Map<dynamic, dynamic>;
                // Cerca un username che corrisponda all'utente corrente
                for (final entry in indexData.entries) {
                  if (entry.value.toString() == userId) {
                    twitterUsername = entry.key.toString();
                    break;
                  }
                }
              }
            } catch (e) {
              print('DEBUG: Errore nel recupero dell\'indice Twitter: $e');
            }
          }
          
          print('DEBUG: Twitter username trovato: $twitterUsername');
          
          // Se non abbiamo un ID del tweet, proviamo a recuperarlo dalle pubblicazioni recenti
          if (twitterId.isEmpty) {
            try {
              // Controlla se ci sono tweet recenti in uploads o videos
              if (userData.containsKey('uploads')) {
                final uploads = userData['uploads'] as Map<dynamic, dynamic>;
                // Ordina gli upload per timestamp (più recenti prima)
                final sortedUploads = uploads.entries.toList()
                  ..sort((a, b) {
                    final timestampA = (a.value as Map<dynamic, dynamic>)['timestamp'] ?? 0;
                    final timestampB = (b.value as Map<dynamic, dynamic>)['timestamp'] ?? 0;
                    return (timestampB as int).compareTo(timestampA as int);
                  });
                
                // Cerca un upload recente con Twitter
                for (final upload in sortedUploads) {
                  final uploadData = upload.value as Map<dynamic, dynamic>;
                  if (uploadData.containsKey('publishedAccounts') && 
                      uploadData['publishedAccounts'] is Map &&
                      uploadData['publishedAccounts'].containsKey('Twitter')) {
                    // Abbiamo trovato un post Twitter, vediamo se ha un post_id
                    final twitterAccounts = uploadData['publishedAccounts']['Twitter'] as List;
                    for (final account in twitterAccounts) {
                      if (account is Map && account.containsKey('post_id')) {
                        twitterId = account['post_id'].toString();
                        print('DEBUG: Twitter post ID trovato negli uploads: $twitterId');
                        break;
                      }
                    }
                    if (twitterId.isNotEmpty) break;
                  }
                }
              }
            } catch (e) {
              print('DEBUG: Errore nel recupero del Twitter post ID: $e');
            }
          }
          
          if (twitterId.isNotEmpty && twitterUsername != null) {
            url = 'https://analytics.x.com/i/adsmanager/profiles/$twitterUsername/tweets/$twitterId/organic/details';
            print('DEBUG: URL Twitter completo costruito: $url');
          } else {
            // Se non abbiamo l'ID specifico del tweet, andiamo alla dashboard generale
            if (twitterUsername != null) {
              url = 'https://analytics.x.com/i/adsmanager/profiles/$twitterUsername/tweets';
              print('DEBUG: URL Twitter per tutti i tweet: $url');
            } else {
              url = 'https://analytics.x.com/';
              print('DEBUG: URL Twitter generico: $url');
            }
          }
          break;
          
        case 'threads':
          // Per Threads, usiamo la stessa logica di video_details_page.dart per ottenere il permalink diretto
          try {
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null) {
              final db = FirebaseDatabase.instance.ref();
              final videoId = widget.video['id']?.toString();
              final userId = widget.video['user_id']?.toString();
              
              if (videoId != null && userId != null) {
                // Controlla se è formato nuovo
                final isNewFormat = videoId.contains(userId);
                
                String? postId;
                String? accountId;
                
                if (isNewFormat) {
                  // --- FORMATO NUOVO: users/users/[uid]/videos/[idvideo]/accounts/Threads/ ---
                  final videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Threads');
                  final videoAccountsSnap = await videoAccountsRef.get();
                  if (videoAccountsSnap.exists) {
                    final videoAccounts = videoAccountsSnap.value;
                    
                    if (videoAccounts is Map) {
                      // Caso: un solo account per piattaforma (oggetto diretto)
                      postId = videoAccounts['post_id']?.toString();
                      accountId = videoAccounts['account_id']?.toString();
                    } else if (videoAccounts is List) {
                      // Caso: più account per piattaforma (lista di oggetti)
                      for (final accountData in videoAccounts) {
                        if (accountData is Map) {
                          postId = accountData['post_id']?.toString();
                          accountId = accountData['account_id']?.toString();
                          break; // Prendi il primo
                        }
                      }
                    }
                  }
                } else {
                  // --- FORMATO VECCHIO: users/users/[uid]/videos/[idvideo]/accounts/Threads/[numero]/ ---
                  final videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Threads');
                  final videoAccountsSnap = await videoAccountsRef.get();
                  if (videoAccountsSnap.exists) {
                    final videoAccounts = videoAccountsSnap.value as List<dynamic>;
                    
                    if (videoAccounts.isNotEmpty) {
                      final accountData = videoAccounts.first as Map<dynamic, dynamic>;
                      postId = accountData['post_id']?.toString();
                      accountId = accountData['id']?.toString();
                    }
                  }
                }
                
                if (postId != null && postId.isNotEmpty && accountId != null && accountId.isNotEmpty) {
                  // Prendi l'access token dal path users/users/[uid]/social_accounts/threads/[accountId]/access_token
                  final accessTokenSnap = await db.child('users').child('users').child(currentUser.uid).child('social_accounts').child('threads').child(accountId).child('access_token').get();
                  String? accessToken;
                  if (accessTokenSnap.exists) {
                    accessToken = accessTokenSnap.value?.toString();
                    print('[THREADS] Access token trovato per accountId $accountId');
                  }
                  
                  if (accessToken != null && accessToken.isNotEmpty) {
                    // Chiamata API per ottenere il permalink: GET https://graph.threads.net/v1.0/{media_id}?fields=permalink&access_token=...
                    final apiUrl = 'https://graph.threads.net/v1.0/$postId?fields=permalink&access_token=$accessToken';
                    print('[THREADS] Chiamata API: $apiUrl');
                    
                    final response = await http.get(Uri.parse(apiUrl));
                    if (response.statusCode == 200) {
                      final data = jsonDecode(response.body);
                      if (data != null && data['permalink'] != null) {
                        url = data['permalink'].toString();
                        print('[THREADS] Permalink ottenuto: $url');
                      } else {
                        print('[THREADS] Nessun permalink nella risposta');
                      }
                    } else {
                      print('[THREADS] Errore API: ${response.statusCode}');
                    }
                  } else {
                    print('[THREADS] Nessun access token valido');
                  }
          } else {
                  print('[THREADS] Nessun post_id o accountId trovato');
                }
              }
            }
          } catch (e) {
            print('[THREADS] Errore durante il fetch del permalink: $e');
          }
          
          // Se non riusciamo a ottenere il permalink, usa un fallback generico
          if (url == null || url.isEmpty) {
            url = 'https://www.threads.net/';
            print('[THREADS] Fallback su URL generico: $url');
          }
          break;
          
        default:
          print('DEBUG: Piattaforma non riconosciuta: $platform');
          _mostraErrore('Piattaforma non supportata: $platform');
          return;
      }
      
      // Debug log - URL finale
      print('DEBUG: URL finale per $platform: ${url ?? "non disponibile"}');
      
      // Apri l'URL se disponibile
      if (url != null && url.isNotEmpty) {
        try {
          // Assicuriamoci che l'URL sia formattato correttamente
          if (!url.startsWith('http://') && !url.startsWith('https://')) {
            url = 'https://' + url;
            print('DEBUG: URL corretto aggiungendo https://: $url');
          }
          
          final Uri uri = Uri.parse(url);
          print('DEBUG: Tentativo di apertura URI: $uri');
          
          // Gestione speciale per Instagram e Threads
          if (platform.toLowerCase() == 'threads') {
            print('DEBUG: Apertura Threads in browser nativo per garantire login');
            
            // Apri il browser nativo per Threads
            final bool launched = await launchUrl(
              uri,
              mode: LaunchMode.externalNonBrowserApplication, // Forza l'apertura nell'app nativa
              webViewConfiguration: const WebViewConfiguration(
                enableJavaScript: true,
                enableDomStorage: true,
              )
            );
            
            if (launched) {
              print('DEBUG: URL Threads aperto con successo in browser nativo');
            } else {
              print('DEBUG: Fallback all\'apertura di Threads in browser esterno');
              final bool externalLaunched = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication
              );
              
              if (!externalLaunched) {
                _mostraErrore('Impossibile aprire Threads. Assicurati di essere già loggato in un browser.');
              }
            }
          } else if (platform.toLowerCase() == 'instagram') {
            print('DEBUG: Apertura Instagram con gestione differenziata per insights vs profilo');
            
            // Controlla se l'URL è per insights (Facebook Business) o per profilo Instagram
            if (url.contains('business.facebook.com')) {
              // URL per insights - prova prima ad aprire nell'app Facebook Business Suite
              try {
                final bool appLaunched = await launchUrl(
                  uri,
                  mode: LaunchMode.externalNonBrowserApplication
                );
                
                if (appLaunched) {
                  print('DEBUG: Instagram insights aperto nell\'app Facebook Business Suite');
                } else {
                  print('DEBUG: Fallback all\'apertura di Instagram insights in browser esterno');
                  final bool externalLaunched = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication
                  );
                  
                  if (!externalLaunched) {
                    _mostraErrore('Impossibile aprire gli insights Instagram. Prova ad aprire manualmente Facebook Business Suite.');
                  }
                }
              } catch (e) {
                print('DEBUG: Errore nell\'apertura dell\'app, fallback al browser: $e');
                final bool externalLaunched = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication
                );
                
                if (!externalLaunched) {
                  _mostraErrore('Impossibile aprire gli insights Instagram.');
                }
              }
            } else {
              // URL per profilo Instagram - apri nell'app Instagram o nel browser
              try {
                // Prova ad aprire nell'app Instagram
                final bool appLaunched = await launchUrl(
                  uri,
                  mode: LaunchMode.externalNonBrowserApplication
                );
                
                if (appLaunched) {
                  print('DEBUG: Profilo Instagram aperto nell\'app Instagram');
                } else {
                  print('DEBUG: Fallback all\'apertura del profilo Instagram in browser esterno');
                  final bool externalLaunched = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication
                  );
                  
                  if (!externalLaunched) {
                    _mostraErrore('Impossibile aprire il profilo Instagram.');
                  }
                }
              } catch (e) {
                print('DEBUG: Errore nell\'apertura dell\'app Instagram, fallback al browser: $e');
                final bool externalLaunched = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication
                );
                
                if (!externalLaunched) {
                  _mostraErrore('Impossibile aprire il profilo Instagram.');
                }
              }
            }
          } else {
            // Per le altre piattaforme, apri normalmente
            // Verifica se l'URL può essere aperto
            if (await canLaunchUrl(uri)) {
              print('DEBUG: Apertura URL...');
              final bool launched = await launchUrl(
                uri, 
                mode: LaunchMode.externalApplication
              );
              
              if (launched) {
                print('DEBUG: URL aperto con successo');
              } else {
                print('DEBUG: launchUrl ha restituito false');
                _mostraErrore('Impossibile aprire il browser. Riprova più tardi.');
              }
            } else {
              print('DEBUG: Impossibile aprire URL: canLaunchUrl ha restituito false');
              _mostraErrore('Nessuna app disponibile per aprire questo URL: $url');
            }
          }
        } catch (e) {
          print('DEBUG: Errore durante l\'apertura dell\'URL: $e');
          _mostraErrore('Errore: ${e.toString()}');
        }
      } else {
        print('DEBUG: URL non disponibile per la piattaforma $platform');
        _mostraErrore('URL delle analytics non disponibile per questa piattaforma');
      }
    } catch (e) {
      print('DEBUG: Errore generale: $e');
      _mostraErrore('Errore durante il recupero dei dati: ${e.toString()}');
    }
  }

  // Helper per mostrare messaggi di errore
  void _mostraErrore(String messaggio) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messaggio),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  // Funzione per recuperare gli ID degli account da Firebase Database
  Future<Map<String, String>> _getAccountIdsFromFirebase(String userId, String platform) async {
    Map<String, String> accountIds = {};
    
    try {
      // Riferimento al database Firebase
      final databaseRef = FirebaseDatabase.instance.ref();
      
      // Ottieni i dati dell'utente (nuovo formato -> fallback al vecchio)
      DataSnapshot userSnapshot = await databaseRef.child('users').child('users').child(userId).get();
      if (!userSnapshot.exists) {
        userSnapshot = await databaseRef.child('users').child(userId).get();
      }
      if (userSnapshot.exists) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        
        // Controlla se l'utente ha account social per la piattaforma specificata
        if (userData.containsKey('social_accounts') && 
            userData['social_accounts'] is Map && 
            userData['social_accounts'].containsKey(platform)) {
          
          final platformAccounts = userData['social_accounts'][platform] as Map<dynamic, dynamic>;
          
          // Per ogni account della piattaforma
          platformAccounts.forEach((accountId, accountData) {
            if (accountData is Map && accountData.containsKey('username')) {
              final username = accountData['username'].toString();
              accountIds[username] = accountId.toString();
            }
          });
        }
        
        // Controlla anche negli account diretti della piattaforma (struttura alternativa)
        if (userData.containsKey(platform) && userData[platform] is Map) {
          final platformAccounts = userData[platform] as Map<dynamic, dynamic>;
          
          platformAccounts.forEach((accountId, accountData) {
            if (accountData is Map) {
              String username = '';
              if (accountData.containsKey('username')) {
                username = accountData['username'].toString();
              } else if (accountData.containsKey('channel_name')) {
                username = accountData['channel_name'].toString();
              } else if (accountData.containsKey('display_name')) {
                username = accountData['display_name'].toString();
              }
              
              if (username.isNotEmpty) {
                accountIds[username] = accountId.toString();
              }
            }
          });
        }
      }
    } catch (e) {
      print('Errore nel recupero degli ID da Firebase: $e');
    }
    
    return accountIds;
  }
  // Show premium upgrade modal
  void _showPremiumUpgradeModal() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Handle
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 24),
              
              // Premium icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFFFF6B6B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  color: Colors.white,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              
              // Title
              Text(
                'Upgrade to Premium',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              
              // Description
              Text(
                'AI Analysis is a premium feature. Upgrade to access advanced analytics, AI-powered insights, and more.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 24),
              
              // Premium features list
              ...[
                'Videos per day: Unlimited',
                'Platforms: All available',
                'Credits: Unlimited',
                'AI Analysis: Unlimited',
                'Priority support: Premium',
                if (!_hasUsedTrial) '3 days free trial included',
              ].map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check,
                          color: theme.colorScheme.primary,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        feature,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              // Upgrade button
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFFFF6B6B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Platform.isIOS
                            ? const UpgradePremiumIOSPage(suppressExtraPadding: true)
                            : const UpgradePremiumPage(suppressExtraPadding: true),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Upgrade Now',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
  Future<void> _incrementDailyAnalysisCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final databaseRef = FirebaseDatabase.instance.ref();
      final today = DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
      
      final dailyStatsRef = databaseRef.child('users').child('users').child(user.uid).child('daily_analysis_stats');
      final todayRef = dailyStatsRef.child(today);
      
      // Se il giorno di oggi non esiste ancora, elimina tutti i giorni precedenti
      final todaySnapshot = await todayRef.get();
      if (!todaySnapshot.exists) {
        try {
          final allDaysSnapshot = await dailyStatsRef.get();
          if (allDaysSnapshot.exists) {
            for (final day in allDaysSnapshot.children) {
              if (day.key != today) {
                await dailyStatsRef.child(day.key!).remove();
              }
            }
          }
        } catch (e) {
          // In caso di errore nella pulizia, continua comunque con l'incremento di oggi
          print('Errore nella rimozione dei giorni precedenti: $e');
        }
      }
      
      // Incrementa il contatore per oggi
      await todayRef.update({
        'analysis_count': ServerValue.increment(1),
        'last_used': ServerValue.timestamp,
        'date': today,
      });
      
      // Ricarica lo stato aggiornato per impostare correttamente la disponibilità (<5)
      try {
        final refreshed = await todayRef.get();
        if (refreshed.exists) {
          final data = refreshed.value as Map<dynamic, dynamic>;
          final analysisCount = data['analysis_count'] as int? ?? 0;
          if (mounted) {
            setState(() {
              _hasDailyAnalysisAvailable = analysisCount < 5;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _hasDailyAnalysisAvailable = true;
            });
          }
        }
      } catch (_) {}
      
      print('Contatore analisi giornaliere incrementato per l\'utente ${user.uid}');
    } catch (e) {
      print('Errore nell\'incremento del contatore giornaliero: $e');
    }
  }

  void _showDailyLimitReachedModal() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Handle
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 24),
              

              
              // Title
              Text(
                'Daily Limit Reached',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              
              // Description
              Text(
                'You have already used your free AI analysis for today. Come back tomorrow for another free analysis, or upgrade to Premium for unlimited access.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 24),
              
              // Premium features list
              ...[
                'Videos per day: Unlimited',
                'Credits: Unlimited',
                'AI Analysis: Unlimited',
                'Priority support: Premium',
                if (!_hasUsedTrial) '3 days free trial included',
              ].map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check,
                          color: theme.colorScheme.primary,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        feature,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              // Upgrade button
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Platform.isIOS
                            ? const UpgradePremiumIOSPage(suppressExtraPadding: true)
                            : const UpgradePremiumPage(suppressExtraPadding: true),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Upgrade Now',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showCreditsLimitModal() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Handle
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 24),
              // Title centered
              Text(
                'Insufficient Credits',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              // Minimal description (no explicit numbers)
              Text(
                "You've run out of credits for AI analysis. Earn more or upgrade to continue.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey[700],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              // CTA buttons with 135° gradient
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          transform: GradientRotation(135 * 3.14159 / 180),
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF667eea).withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CreditsPage(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Get Credits',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          transform: GradientRotation(135 * 3.14159 / 180),
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF667eea).withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => Platform.isIOS
                                  ? const UpgradePremiumIOSPage(suppressExtraPadding: true)
                                  : const UpgradePremiumPage(suppressExtraPadding: true),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Upgrade',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // Funzione che controlla se ci sono dati disponibili per l'analisi AI
  bool _hasStatsData() {
    // Per utenti non premium: permette sempre l'analisi (con limite giornaliero)
    if (!_isPremium) return true;
    
    // Per utenti premium: almeno una metrica > 0
    // Controlla dati API
    for (final metric in ['likes', 'views', 'comments']) {
      final map = _statsData[metric];
      if (map != null) {
        for (final v in map.values) {
          if (v > 0) return true;
        }
      }
    }
    // Controlla dati manuali
    for (final v in _manualViews.values) {
      if (v > 0) return true;
    }
    for (final v in _manualLikes.values) {
      if (v > 0) return true;
    }
    for (final v in _manualComments.values) {
      if (v > 0) return true;
    }
    return false;
  }

  // --- PERFORMANCE METRICS: override views/likes/comments con manuali se IG senza token ---
  double _getViewsForMetrics(String accountKey) {
    final meta = _accountMeta[accountKey] ?? {};
    final platform = meta['platform'] as String? ?? accountKey.replaceAll(RegExp(r'\d'), '');
    final isIGNoToken = platform == 'instagram' && (meta['missing_token'] == true);
    if (isIGNoToken) {
      return _manualViews[accountKey]?.toDouble() ?? 0;
    }
    if ((platform == 'instagram' || platform == 'facebook' || platform == 'threads')) {
      if (_manualViews[accountKey] != null) {
        return _manualViews[accountKey]!.toDouble();
      } else {
        return 0;
      }
    }
    return _statsData['views']?[accountKey] ?? 0;
  }
  double _getLikesForMetrics(String accountKey) {
    final meta = _accountMeta[accountKey] ?? {};
    final platform = meta['platform'] as String? ?? accountKey.replaceAll(RegExp(r'\d'), '');
    final isIGNoToken = platform == 'instagram' && (meta['missing_token'] == true);
    if (isIGNoToken) {
      return _manualLikes[accountKey]?.toDouble() ?? 0;
    }
    return _statsData['likes']?[accountKey] ?? 0;
  }
  double _getCommentsForMetrics(String accountKey) {
    final meta = _accountMeta[accountKey] ?? {};
    final platform = meta['platform'] as String? ?? accountKey.replaceAll(RegExp(r'\d'), '');
    final isIGNoToken = platform == 'instagram' && (meta['missing_token'] == true);
    if (isIGNoToken) {
      return _manualComments[accountKey]?.toDouble() ?? 0;
    }
    return _statsData['comments']?[accountKey] ?? 0;
  }

  Future<void> _saveAggregatedStatsToFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    final videoId = widget.video['id']?.toString() ?? widget.video['key']?.toString();
    if (user == null || videoId == null) return;

    // Somma likes e comments da tutte le mappe (API e manuali)
    double totalLikes = 0;
    double totalComments = 0;

    // Likes e comments da API
    _statsData['likes']?.forEach((k, v) {
      totalLikes += v;
    });
    _statsData['comments']?.forEach((k, v) {
      totalComments += v;
    });

    // Likes e comments manuali IG/FB/Threads (aggiungi solo se la chiave non è già in _statsData)
    _manualLikes.forEach((k, v) {
      if (!(_statsData['likes']?.containsKey(k) ?? false)) {
        totalLikes += v;
      }
    });
    _manualComments.forEach((k, v) {
      if (!(_statsData['comments']?.containsKey(k) ?? false)) {
        totalComments += v;
      }
    });

    final databaseRef = FirebaseDatabase.instance.ref();
    await databaseRef.child('users').child('users').child(user.uid).child('videos').child(videoId).update({
      'total_likes': totalLikes.toInt(),
      'total_comments': totalComments.toInt(),
      'last_stats_update': DateTime.now().millisecondsSinceEpoch,
    });
  }
}

// Classe per rappresentare una sezione dell'analisi
class AnalysisSection {
  final String title;
  final String content;
  
  AnalysisSection(this.title, this.content);
}

// Classe per rappresentare un messaggio della chat
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<String>? suggestedQuestions; // Domande suggerite per questo messaggio
  
  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.suggestedQuestions,
  });
} 

// Funzione per costruire una colonna del BarChart
BarChartGroupData _buildBarGroup(int x, double y, Color color) {
  return BarChartGroupData(
    x: x,
    barRods: [
      BarChartRodData(
        toY: y,
        color: color,
        width: 22,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        backDrawRodData: BackgroundBarChartRodData(
          show: true,
          toY: y,
          color: Colors.grey.withOpacity(0.1),
        ),
      ),
    ],
    showingTooltipIndicators: [],
  );
}

  // Helper per estrarre le SUGGESTED_QUESTIONS (anche localizzate) e ripulire il testo
  Map<String, Object> _extractSuggestedQuestionsFromText(String text) {
    // Supporta "SUGGESTED_QUESTIONS:", "SUGGESTED QUESTIONS:", "DOMANDE SUGGERITE:" e varianti
    final headerPattern = RegExp(
      r'^(?:\s*)(SUGGESTED[_\s]?QUESTIONS|DOMANDE\s+SUGGERITE)\s*:?\s*$',
      caseSensitive: false,
      multiLine: true,
    );
    final lines = text.split('\n');
    int headerIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (headerPattern.hasMatch(lines[i])) {
        headerIndex = i;
        break;
      }
    }
    if (headerIndex == -1) {
      return {
        'cleanText': text,
        'questions': <String>[],
      };
    }
    final List<String> questions = [];
    int endIndex = headerIndex; // verrà esteso mentre leggiamo domande
    // pattern per linee domanda: numerate o bullet
    final bulletPattern = RegExp(r'^\s*(?:[0-9]+[\)\.-]|[-•*–—])\s*(.+)$');
    for (int i = headerIndex + 1; i < lines.length; i++) {
      final raw = lines[i].trimRight();
      final trimmed = raw.trim();
      // stop conditions: nuova sezione / nota / riga vuota dopo aver iniziato
      final isNote = RegExp(r'^\s*note\s*:', caseSensitive: false).hasMatch(trimmed);
      final isHeaderLike = RegExp(r'^[A-Z][A-Z\s_]+:?$').hasMatch(trimmed);
      if (trimmed.isEmpty && questions.isNotEmpty) {
        endIndex = i - 1;
        break;
      }
      if (isNote || isHeaderLike) {
        endIndex = i - 1;
        break;
      }
      String? qText;
      final bm = bulletPattern.firstMatch(raw);
      if (bm != null) {
        qText = bm.group(1)?.trim();
      } else if (trimmed.isNotEmpty) {
        // accetta anche righe non marcate come domanda
        qText = trimmed;
      }
      if (qText != null && qText.isNotEmpty) {
        questions.add(fixEncoding(qText));
        endIndex = i;
        if (questions.length >= 3) {
          break; // limitiamo a 3
        }
      }
    }
    // se nessuna domanda valida trovata, ritorna testo originale
    if (questions.isEmpty) {
      return {
        'cleanText': text,
        'questions': <String>[],
      };
    }
    // ricostruisci il testo senza il blocco header..endIndex
    final cleaned = [
      ...lines.sublist(0, headerIndex),
      ...lines.sublist(endIndex + 1),
    ].join('\n').trim();
    return {
      'cleanText': cleaned,
      'questions': questions,
    };
}

// Funzione per correggere encoding errato (es: caratteri accentati e apostrofi)
String fixEncoding(String input) {
  try {
    // Prima prova la decodifica UTF-8
    String result = utf8.decode(latin1.encode(input));
    
    // Correggi gli apostrofi comuni
    result = result.replaceAll('â€™', "'"); // apostrofo tipografico
    result = result.replaceAll('â€œ', '"'); // virgolette aperte
    result = result.replaceAll('â€', '"'); // virgolette chiuse
    result = result.replaceAll('â€"', '—'); // em dash
    result = result.replaceAll('â€"', '–'); // en dash
    result = result.replaceAll('â€¦', '…'); // ellipsis
    
    return result;
  } catch (e) {
    // Se la decodifica fallisce, prova a correggere solo gli apostrofi
    String result = input;
    result = result.replaceAll('â€™', "'");
    result = result.replaceAll('â€œ', '"');
    result = result.replaceAll('â€', '"');
    result = result.replaceAll('â€"', '—');
    result = result.replaceAll('â€"', '–');
    result = result.replaceAll('â€¦', '…');
    return result;
  }
}
// --- WIDGET PERSONALIZZATO PER LA RIGA DELLE VISUALIZZAZIONI ---
class _ManualViewsRow extends StatefulWidget {
  final String accountKey;
  final int value;
  final ValueChanged<int> onValueChanged;
  final String videoId;
  final String socialmedia;
  final String username;
  final String displayName;
  final String uid;
  const _ManualViewsRow({
    required this.accountKey,
    required this.value,
    required this.onValueChanged,
    required this.videoId,
    required this.socialmedia,
    required this.username,
    required this.displayName,
    required this.uid,
  });
  @override
  State<_ManualViewsRow> createState() => _ManualViewsRowState();
}

// --- GENERIC WIDGET PER MANUAL STATS (views, likes, comments) ---
class _ManualStatRow extends StatefulWidget {
  final String accountKey;
  final int value;
  final ValueChanged<int> onValueChanged;
  final String videoId;
  final String socialmedia;
  final String username;
  final String displayName;
  final String uid;
  final String label;
  final String firebaseKey; // es: manual_views, manual_likes, manual_comments
  const _ManualStatRow({
    required this.accountKey,
    required this.value,
    required this.onValueChanged,
    required this.videoId,
    required this.socialmedia,
    required this.username,
    required this.displayName,
    required this.uid,
    required this.label,
    required this.firebaseKey,
  });
  @override
  State<_ManualStatRow> createState() => _ManualStatRowState();
}

class _ManualStatRowState extends State<_ManualStatRow> {
  late TextEditingController _controller;
  FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value > 0 ? widget.value.toString() : '');
  }

  Future<void> _saveValue() async {
    final value = int.tryParse(_controller.text.trim());
    widget.onValueChanged(value ?? 0);
    // --- Salva su Firebase ---
    try {
      if (widget.uid.isEmpty || widget.videoId.isEmpty || widget.socialmedia.isEmpty) {
        print('[manual_stat] Dati mancanti: uid=[36m${widget.uid}[0m, videoId=[36m${widget.videoId}[0m, socialmedia=[36m${widget.socialmedia}[0m, username=${widget.username}, displayName=${widget.displayName}');
        return;
      }
      final db = FirebaseDatabase.instance.ref();
      final socialmediaPath = widget.socialmedia[0].toUpperCase() + widget.socialmedia.substring(1);
      print('[manual_stat] Inizio salvataggio. UID: ${widget.uid}, videoId: ${widget.videoId}, socialmedia: $socialmediaPath, username: ${widget.username}, displayName: ${widget.displayName}, valore: $value, key: ${widget.firebaseKey}');
      final accountsSnap = await db.child('users').child('users').child(widget.uid).child('videos').child(widget.videoId).child('accounts').child(socialmediaPath).get();
      if (!accountsSnap.exists) { print('[manual_stat] Nessun account trovato per $socialmediaPath'); return; }
      final accounts = accountsSnap.value;
      int foundIndex = -1;
      String foundKey = '';
      if (accounts is Map) {
        for (final entry in accounts.entries) {
          final key = entry.key.toString();
          final acc = entry.value;
          if (acc is Map) {
            final accUser = (acc['account_username'] ?? acc['username'] ?? '').toString().trim().toLowerCase();
            final accDisplay = (acc['account_display_name'] ?? acc['display_name'] ?? '').toString().trim().toLowerCase();
            final searchUser = widget.username.trim().toLowerCase();
            final searchDisplay = widget.displayName.trim().toLowerCase();
            if ((searchUser.isNotEmpty && accUser == searchUser) ||
                (searchDisplay.isNotEmpty && accDisplay == searchDisplay)) {
              foundIndex = 1; // dummy, not used
              foundKey = key;
              break;
            }
          }
        }
      } else if (accounts is List) {
        for (int i = 0; i < accounts.length; i++) {
          final acc = accounts[i];
          if (acc is Map) {
            final accUser = (acc['account_username'] ?? acc['username'] ?? '').toString().trim().toLowerCase();
            final accDisplay = (acc['account_display_name'] ?? acc['display_name'] ?? '').toString().trim().toLowerCase();
            final searchUser = widget.username.trim().toLowerCase();
            final searchDisplay = widget.displayName.trim().toLowerCase();
            if ((searchUser.isNotEmpty && accUser == searchUser) ||
                (searchDisplay.isNotEmpty && accDisplay == searchDisplay)) {
              foundIndex = i;
              foundKey = i.toString();
              break;
            }
          }
        }
      }
      print('[manual_stat] Chiave trovata: $foundKey');
      if (foundKey.isNotEmpty) {
        final path = 'users/users/${widget.uid}/videos/${widget.videoId}/accounts/$socialmediaPath/$foundKey/${widget.firebaseKey}';
        print('[manual_stat] Salvo in: $path valore: ${value ?? 0}');
        await db.child('users').child('users').child(widget.uid).child('videos').child(widget.videoId).child('accounts').child(socialmediaPath).child(foundKey).update({
          widget.firebaseKey: value ?? 0,
        });
        print('[manual_stat] Salvataggio completato con successo!');
      } else {
        print('[manual_stat] Nessun account corrispondente trovato per username/displayName: ${widget.username} / ${widget.displayName}');
      }
    } catch (e) {
      print('[manual_stat] Errore salvataggio ${widget.firebaseKey} su Firebase: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: widget.label,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      ),
      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
      onEditingComplete: _saveValue,
      onSubmitted: (_) {
        _saveValue();
        FocusScope.of(context).unfocus();
      },
    );
  }
}
class _ManualViewsRowState extends State<_ManualViewsRow> {
  late TextEditingController _controller;
  FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value > 0 ? widget.value.toString() : '');
  }

  Future<void> _saveValue() async {
    final value = int.tryParse(_controller.text.trim());
    widget.onValueChanged(value ?? 0);
    // --- Salva su Firebase ---
    try {
      if (widget.uid.isEmpty || widget.videoId.isEmpty || widget.socialmedia.isEmpty) {
        print('[manual_views] Dati mancanti: uid=${widget.uid}, videoId=${widget.videoId}, socialmedia=${widget.socialmedia}, username=${widget.username}, displayName=${widget.displayName}');
        return;
      }
      final db = FirebaseDatabase.instance.ref();
      final socialmediaPath = widget.socialmedia[0].toUpperCase() + widget.socialmedia.substring(1);
      print('[manual_views] Inizio salvataggio. UID: ${widget.uid}, videoId: ${widget.videoId}, socialmedia: $socialmediaPath, username: ${widget.username}, displayName: ${widget.displayName}, valore: $value');
      final accountsSnap = await db.child('users').child('users').child(widget.uid).child('videos').child(widget.videoId).child('accounts').child(socialmediaPath).get();
      if (!accountsSnap.exists) { print('[manual_views] Nessun account trovato per $socialmediaPath'); return; }
      final accounts = accountsSnap.value;
      int foundIndex = -1;
      String foundKey = '';
      if (accounts is Map) {
        for (final entry in accounts.entries) {
          final key = entry.key.toString();
          final acc = entry.value;
          if (acc is Map) {
            final accUser = (acc['account_username'] ?? acc['username'] ?? '').toString().trim().toLowerCase();
            final accDisplay = (acc['account_display_name'] ?? acc['display_name'] ?? '').toString().trim().toLowerCase();
            final searchUser = widget.username.trim().toLowerCase();
            final searchDisplay = widget.displayName.trim().toLowerCase();
            print('[manual_views] Chiave: $key, account_username: $accUser, display_name: $accDisplay');
            if ((searchUser.isNotEmpty && accUser == searchUser) ||
                (searchDisplay.isNotEmpty && accDisplay == searchDisplay)) {
              foundIndex = 1; // dummy, not used
              foundKey = key;
              break;
            }
          }
        }
      } else if (accounts is List) {
        for (int i = 0; i < accounts.length; i++) {
          final acc = accounts[i];
          if (acc is Map) {
            final accUser = (acc['account_username'] ?? acc['username'] ?? '').toString().trim().toLowerCase();
            final accDisplay = (acc['account_display_name'] ?? acc['display_name'] ?? '').toString().trim().toLowerCase();
            final searchUser = widget.username.trim().toLowerCase();
            final searchDisplay = widget.displayName.trim().toLowerCase();
            print('[manual_views] Indice: $i, account_username: $accUser, display_name: $accDisplay');
            if ((searchUser.isNotEmpty && accUser == searchUser) ||
                (searchDisplay.isNotEmpty && accDisplay == searchDisplay)) {
              foundIndex = i;
              foundKey = i.toString();
              break;
            }
          }
        }
      }
      print('[manual_views] Chiave trovata: $foundKey');
      if (foundKey.isNotEmpty) {
        final path = 'users/users/${widget.uid}/videos/${widget.videoId}/accounts/$socialmediaPath/$foundKey/manual_views';
        print('[manual_views] Salvo in: $path valore: ${value ?? 0}');
        await db.child('users').child('users').child(widget.uid).child('videos').child(widget.videoId).child('accounts').child(socialmediaPath).child(foundKey).update({
          'manual_views': value ?? 0,
        });
        print('[manual_views] Salvataggio completato con successo!');
      } else {
        print('[manual_views] Nessun account corrispondente trovato per username/displayName: ${widget.username} / ${widget.displayName}');
      }
    } catch (e) {
      print('[manual_views] Errore salvataggio manual_views su Firebase: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: 'Views',
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      ),
      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
      onEditingComplete: _saveValue,
      onSubmitted: (_) {
        _saveValue();
        FocusScope.of(context).unfocus();
      },
    );
  }
} 