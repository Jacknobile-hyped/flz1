import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis/youtube/v3.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_sign_in/google_sign_in.dart';

class YouTubeService {
  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/youtube.upload',
    'https://www.googleapis.com/auth/youtube',
    'https://www.googleapis.com/auth/youtube.force-ssl'
  ];
  static const String _clientId = '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com'; // Web client ID
  static const String _clientSecret = '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'; // Client secret
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/youtube.upload',
      'https://www.googleapis.com/auth/youtube.readonly',
      'https://www.googleapis.com/auth/youtube',
      'https://www.googleapis.com/auth/youtube.force-ssl'
    ],
    clientId: '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com',
  );

  // Carica un video su YouTube con una data di pubblicazione programmata utilizzando gli account già autorizzati
  Future<String?> uploadScheduledVideoWithSavedAccount({
    required File videoFile, 
    required String title, 
    required String description, 
    required DateTime publishAt,
    required String accountId,
    List<String> tags = const [],
    Map<String, dynamic>? youtubeOptions,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Tenta di usare GoogleSignIn per ottenere l'account già autenticato
      GoogleSignInAccount? googleUser;
      
      try {
        // Prova a ottenere l'account già autorizzato
        googleUser = await _googleSignIn.signInSilently();
        
        // Se non c'è un account già autorizzato, richiedi l'accesso
        if (googleUser == null) {
          googleUser = await _googleSignIn.signIn();
        }
        
        if (googleUser == null) {
          throw Exception('Google sign in failed');
        }
      } catch (e) {
        print('Error signing in with Google: $e');
        // Fallback alla vecchia autorizzazione se GoogleSignIn fallisce
        return await uploadScheduledVideo(
          videoFile: videoFile, 
          title: title, 
          description: description, 
          publishAt: publishAt,
          tags: tags
        );
      }

      // Ottieni l'autenticazione
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      if (googleAuth.accessToken == null) {
        throw Exception('Failed to get access token');
      }

      // Crea un client HTTP con il token di accesso
      final authClient = AuthClient(googleAuth.accessToken!);
      
      // Creazione dell'API YouTube
      final youtube = YouTubeApi(authClient);
      
      // Get YouTube options with defaults
      final options = youtubeOptions ?? {
        'categoryId': '22',
        'privacyStatus': 'private', // Per scheduling deve essere private
        'license': 'youtube',
        'notifySubscribers': true,
        'embeddable': true,
        'madeForKids': false,
      };
      
      // Preparazione dei metadati del video con opzioni utente
      final video = Video(
        snippet: VideoSnippet(
          title: title,
          description: description,
          tags: tags,
          categoryId: options['categoryId'] ?? '22',
        ),
        status: VideoStatus(
          privacyStatus: options['privacyStatus'] ?? 'private', // Per scheduling deve essere private
          publishAt: publishAt.toUtc(), // Formato RFC3339 richiesto dalla documentazione
          license: options['license'] ?? 'youtube',
          embeddable: options['embeddable'] ?? true,
          selfDeclaredMadeForKids: options['madeForKids'] ?? false,
        ),
      );

      print('YouTube upload parameters:');
      print('Title: $title');
      print('Description: $description');
      print('Privacy Status: private');
      print('Publish At (UTC): ${publishAt.toUtc()}');
      print('Publish At (RFC3339): ${publishAt.toUtc().toIso8601String()}');

      // Upload del video
      final media = Media(
        videoFile.openRead(),
        videoFile.lengthSync(),
        contentType: 'video/${path.extension(videoFile.path).replaceAll('.', '')}',
      );

      // Esegui l'upload
      final uploadedVideo = await youtube.videos.insert(
        video,
        ['snippet', 'status'],
        uploadMedia: media,
      );

      // Salva i token per possibile uso futuro
      await _saveTokens(googleAuth.accessToken!, googleAuth.idToken!);
      
      return uploadedVideo.id;
    } catch (e) {
      print('Errore durante l\'upload del video su YouTube: $e');
      return null;
    }
  }

  // Carica un video su YouTube con una data di pubblicazione programmata
  Future<String?> uploadScheduledVideo({
    required File videoFile, 
    required String title, 
    required String description, 
    required DateTime publishAt,
    List<String> tags = const []
  }) async {
    try {
      // Configurazione delle credenziali OAuth
      final credentials = ClientId(_clientId, _clientSecret);
      
      // Prompt utente per autorizzazione
      final client = await clientViaUserConsent(
        credentials, 
        _scopes,
        (url) async {
          if (await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(Uri.parse(url));
          } else {
            throw 'Non è possibile aprire il browser per l\'autorizzazione: $url';
          }
        }
      );

      // Salva i token per usi futuri
      await _saveTokens(client.credentials.accessToken.data, client.credentials.refreshToken!);

      // Creazione dell'API YouTube
      final youtube = YouTubeApi(client);
      
      // Preparazione dei metadati del video
      final video = Video(
        snippet: VideoSnippet(
          title: title,
          description: description,
          tags: tags,
          categoryId: '22', // Categoria "People & Blogs"
        ),
        status: VideoStatus(
          privacyStatus: 'private',
          publishAt: publishAt.toUtc(),
        ),
      );

      print('YouTube upload parameters (fallback method):');
      print('Title: $title');
      print('Description: $description');
      print('Privacy Status: private');
      print('Publish At (UTC): ${publishAt.toUtc()}');
      print('Publish At (RFC3339): ${publishAt.toUtc().toIso8601String()}');

      // Upload del video
      final media = Media(
        videoFile.openRead(),
        videoFile.lengthSync(),
        contentType: 'video/${path.extension(videoFile.path).replaceAll('.', '')}',
      );

      // Esegui l'upload
      final uploadedVideo = await youtube.videos.insert(
        video,
        ['snippet', 'status'],
        uploadMedia: media,
      );

      // Chiudi il client
      client.close();
      
      return uploadedVideo.id;
    } catch (e) {
      print('Errore durante l\'upload del video su YouTube: $e');
      return null;
    }
  }
  
  // Validate if the given date is valid for YouTube scheduling
  bool isValidPublishDate(DateTime scheduledDate) {
    // YouTube requires scheduling time to be at least 15 minutes in the future
    final minScheduleTime = DateTime.now().add(Duration(minutes: 15));
    return scheduledDate.isAfter(minScheduleTime);
  }
  
  // Salva i token OAuth direttamente nel database Firebase
  Future<void> _saveTokens(String accessToken, String refreshToken) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Salva i token nel database Firebase
      await _database
          .child('users')
          .child(currentUser.uid)
          .child('youtube_tokens')
          .set({
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': DateTime.now().add(Duration(hours: 1)).millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      print('YouTube tokens saved successfully to Firebase');
    } catch (e) {
      print('Errore durante il salvataggio dei token YouTube: $e');
      // Non rilanciare l'errore per non interrompere il processo di upload
    }
  }
  
  // Verifica lo stato di un video programmato
  Future<Map<String, dynamic>?> checkVideoStatus(String videoId) async {
    try {
      // Prova prima con GoogleSignIn
      try {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
        if (googleUser != null) {
          final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
          if (googleAuth.accessToken != null) {
            // Utilizzare direttamente l'API YouTube per controllare lo stato del video
            final authClient = AuthClient(googleAuth.accessToken!);
            final youtube = YouTubeApi(authClient);
            
            try {
              final video = await youtube.videos.list(
                ['status', 'snippet'],
                id: [videoId],
              );
              
              if (video.items != null && video.items!.isNotEmpty) {
                final videoData = video.items!.first;
                return {
                  'id': videoData.id,
                  'status': videoData.status?.privacyStatus,
                  'publishAt': videoData.status?.publishAt?.toIso8601String(),
                  'title': videoData.snippet?.title,
                  'description': videoData.snippet?.description,
                };
              }
            } catch (youtubeError) {
              print('Errore durante il controllo diretto con GoogleSignIn: $youtubeError');
            } finally {
              authClient.close();
            }
          }
        }
      } catch (signInError) {
        print('Errore durante l\'accesso con GoogleSignIn: $signInError');
      }
      
      // Se GoogleSignIn fallisce, restituisci null
      return null;
    } catch (e) {
      print('Errore durante il controllo dello stato del video YouTube: $e');
      return null;
    }
  }
  
  // Elimina un video da YouTube
  Future<bool> deleteYouTubeVideo(String videoId) async {
    try {
      // Prima proviamo con l'autenticazione GoogleSignIn
      try {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
        if (googleUser != null) {
          final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
          if (googleAuth.accessToken != null) {
            // Utilizzare direttamente l'API YouTube per eliminare il video
            final authClient = AuthClient(googleAuth.accessToken!);
            final youtube = YouTubeApi(authClient);
            
            try {
              await youtube.videos.delete(videoId);
              print('Video eliminato con successo utilizzando GoogleSignIn');
              return true;
            } catch (youtubeError) {
              print('Errore durante l\'eliminazione diretta con GoogleSignIn: $youtubeError');
              // Gestione specifica dell'errore not-found
              final errorMessage = youtubeError.toString();
              if (errorMessage.contains('not-found') || 
                  errorMessage.contains('NOT_FOUND') ||
                  errorMessage.contains('permission-denied') ||
                  errorMessage.contains('Permission denied')) {
                print('Il video $videoId potrebbe essere già stato eliminato o non è più accessibile: $youtubeError');
                return true; // Consideriamo l'operazione come riuscita
              }
            } finally {
              authClient.close();
            }
          }
        }
      } catch (signInError) {
        print('Errore durante l\'accesso con GoogleSignIn: $signInError');
      }
      
      // Se GoogleSignIn fallisce, restituisci false
      return false;
    } catch (e) {
      print('Errore durante l\'eliminazione del video YouTube: $e');
      return false;
    }
  }
  
  // Mostra un dialog di autenticazione YouTube
  Future<bool> showAuthDialog(BuildContext context) async {
    try {
      // Configurazione delle credenziali OAuth
      final credentials = ClientId(_clientId, _clientSecret);
      
      // Prompt utente per autorizzazione
      final client = await clientViaUserConsent(
        credentials, 
        _scopes,
        (url) async {
          if (await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            );
            
            // Mostra dialog per confermare autorizzazione
            final result = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: Text('Autenticazione YouTube'),
                content: Text('Hai completato l\'autenticazione nel browser?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Annulla'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text('Ho completato l\'autorizzazione'),
                  ),
                ],
              ),
            );
            
            // Non restituiamo un valore direttamente
            if (result == false) {
              throw 'Autenticazione annullata dall\'utente';
            }
          } else {
            throw 'Non è possibile aprire il browser per l\'autorizzazione: $url';
          }
        }
      );
      
      // Salva i token per usi futuri
      await _saveTokens(client.credentials.accessToken.data, client.credentials.refreshToken!);
      
      // Chiudi il client
      client.close();
      
      return true;
    } catch (e) {
      print('Errore durante l\'autenticazione YouTube: $e');
      return false;
    }
  }
}

// Cliente di autenticazione semplice per API YouTube
class AuthClient extends http.BaseClient {
  final String accessToken;
  final http.Client _inner = http.Client();

  AuthClient(this.accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $accessToken';
    return _inner.send(request);
  }
  
  void close() {
    _inner.close();
  }
} 