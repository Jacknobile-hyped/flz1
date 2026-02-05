import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_editor/video_editor.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'upload_video_page.dart';
import '../services/video_trimmer_service.dart';

// Widget personalizzato per la timeline con formattazione del tempo migliorata
class CustomTrimTimeline extends StatelessWidget {
  final VideoEditorController controller;
  final EdgeInsets? padding;

  const CustomTrimTimeline({
    Key? key,
    required this.controller,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller.video,
      builder: (context, videoValue, child) {
        return Column(
          children: [
            // Timeline con thumbnails spostate a sinistra
            Container(
              height: 60,
              child: Transform.translate(
                offset: Offset(-10, 0), // Sposta mezzo centimetro a destra (da -20 a -1)
                child: TrimSlider(
                  controller: controller,
                  height: 60,
                  horizontalMargin: 0,
                ),
              ),
            ),
            // Marker temporali personalizzati
            Container(
              height: 20,
              child: Row(
                children: _buildTimeMarkers(videoValue.duration),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildTimeMarkers(Duration duration) {
    final markers = <Widget>[];
    final totalSeconds = duration.inSeconds;
    
    // Per video brevi, usa più marker con mezzi valori
    int markerCount;
    if (totalSeconds <= 10) {
      markerCount = 6; // Più marker per video brevi
    } else if (totalSeconds <= 30) {
      markerCount = 7;
    } else {
      markerCount = 8; // Numero standard per video lunghi
    }
    
    for (int i = 0; i < markerCount; i++) {
      final progress = i / (markerCount - 1);
      final seconds = progress * totalSeconds; // Non arrotondare per permettere mezzi valori
      final timeText = _formatTime(seconds);
      
      markers.add(
        Expanded(
          child: Center(
            child: Text(
              timeText,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }
    
    return markers;
  }

  String _formatTime(double totalSeconds) {
    if (totalSeconds < 60) {
      // Per valori decimali, mostra un decimale se necessario
      if (totalSeconds == totalSeconds.roundToDouble()) {
        return '${totalSeconds.round()}s';
      } else {
        return '${totalSeconds.toStringAsFixed(1)}s';
      }
    } else {
      final minutes = (totalSeconds / 60).floor();
      final seconds = totalSeconds % 60;
      return '${minutes}.${seconds.toStringAsFixed(1).padLeft(3, '0')}';
    }
  }
}

class VideoEditorPage extends StatefulWidget {
  final File videoFile;
  
  const VideoEditorPage({
    Key? key,
    required this.videoFile,
  }) : super(key: key);

  @override
  State<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends State<VideoEditorPage> {
  late VideoEditorController _controller;
  bool _isExporting = false;
  bool _isTrimming = false;
  double _exportProgress = 0.0;
  double _trimProgress = 0.0;
  
  // Variabili per gestire i controlli video
  bool _showVideoControls = true;
  
  // Variabili per la progress bar del video
  Duration _currentPosition = Duration.zero;
  Duration _videoDuration = Duration.zero;
  Timer? _positionUpdateTimer;
  
  // Stream subscription per evitare errori di stream già ascoltato
  StreamSubscription? _progressSubscription;
  
  // Timer per il caricamento graduale
  Timer? _fakeProgressTimer;

  // File attualmente visualizzato (originale o tagliato)
  late File _currentVideoFile;

  @override
  void initState() {
    super.initState();
    _currentVideoFile = widget.videoFile;
    _initializeEditor();
    _applyEditorSystemUiStyle();
  }

  void _initializeEditor() {
    _controller = VideoEditorController.file(
      widget.videoFile,
      minDuration: const Duration(seconds: 1),
      maxDuration: const Duration(minutes: 120), // Aumentato a 2 ore per gestire video molto lunghi
    );
    
    _controller.initialize().then((_) {
      setState(() {
        _videoDuration = _controller.video.value.duration;
        _currentPosition = _controller.video.value.position;
      });
      
      // Avvia il timer per aggiornare la posizione
      _startPositionUpdateTimer();
    });
  }

  @override
  void dispose() {
    _restoreDefaultSystemUiStyle();
    _controller.dispose();
    _positionUpdateTimer?.cancel();
    _progressSubscription?.cancel();
    _fakeProgressTimer?.cancel();
    super.dispose();
  }

  void _startPositionUpdateTimer() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      if (_controller.video.value.isInitialized && mounted) {
        setState(() {
          _currentPosition = _controller.video.value.position;
          _videoDuration = _controller.video.value.duration;
        });
      }
    });
  }

  void _applyEditorSystemUiStyle() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  void _restoreDefaultSystemUiStyle() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Platform.isIOS ? Colors.transparent : (isDark ? const Color(0xFF121212) : Colors.white),
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Platform.isIOS ? Colors.transparent : (isDark ? const Color(0xFF121212) : Colors.white),
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          '',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () async {
            // Torna a UploadVideoPage e forza la selezione video
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => UploadVideoPage(forcePickVideo: true),
              ),
              (route) => false,
            );
          },
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.check, color: Colors.white),
            onPressed: _isExporting ? null : _proceedToNext,
          ),
        ],
      ),
      body: _controller.initialized
          ? Stack(
              children: [
                Column(
                  children: [
                    Flexible(
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _showVideoControls = !_showVideoControls;
                            });
                          },
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 400),
                            curve: Curves.easeInOutCubic,
                            margin: _showVideoControls ? EdgeInsets.all(16) : EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.1),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                )
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: AspectRatio(
                                aspectRatio: _controller.video.value.aspectRatio,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    VideoPlayer(_controller.video),
                                    if (!_controller.isPlaying)
                                      Container(
                                        color: Colors.black.withOpacity(0.3),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: Duration(milliseconds: 350),
                      switchInCurve: Curves.easeInOut,
                      switchOutCurve: Curves.easeInOut,
                      child: _showVideoControls
                          ? Column(
                              key: ValueKey('controls'),
                              children: [
                                // Timeline editor con stile migliorato
                    Container(
                                  height: 140,
                      margin: EdgeInsets.all(16),
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Area trimmer
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return Center(
                                  child: Container(
                                    width: constraints.maxWidth * 0.95,
                                    child: CustomTrimTimeline(
                                      controller: _controller,
                                      padding: const EdgeInsets.only(top: 4),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          // Simplified buttons - no text
                          Container(
                            height: 50,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: _isTrimming ? null : _trimVideo,
                                  icon: Icon(
                                    Icons.content_cut,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  tooltip: 'Taglia video',
                                ),
                                SizedBox(width: 20),
                                IconButton(
                                  onPressed: () {
                                    if (_controller.isPlaying) {
                                      _controller.video.pause();
                                    } else {
                                      _controller.video.play();
                                    }
                                    setState(() {});
                                  },
                                  icon: Icon(
                                    _controller.isPlaying ? Icons.pause : Icons.play_arrow,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  tooltip: _controller.isPlaying ? 'Pausa' : 'Play',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                                ),
                              ],
                            )
                          : SizedBox.shrink(),
                    ),
                  ],
                ),
                
                // Progress overlay
                if (_isExporting || _isTrimming)
                  Container(
                    color: Colors.black.withOpacity(0.9),
                    child: Center(
                      child: Container(
                        width: 200,
                        padding: EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 20,
                              spreadRadius: 0,
                            )
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 60,
                              height: 60,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value: _isExporting ? _exportProgress : _trimProgress,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    strokeWidth: 4,
                                    backgroundColor: Colors.white.withOpacity(0.1),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 20),
                            Text(
                              '${((_isExporting ? _exportProgress : _trimProgress) * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              _isExporting 
                                  ? 'Video processing'
                                  : 'Video editing',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 60,
                      height: 60,
                      child: CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                        strokeWidth: 6,
                      ),
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Video loading...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'This may take a few seconds',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _trimVideo() async {
    setState(() {
      _isTrimming = true;
      _trimProgress = 0.0;
    });
    
    // Avvia il caricamento graduale fino all'80%
    _startFakeProgress();
    
    try {
      // Verifica se il server è disponibile
      final isServerAvailable = await VideoTrimmerService.isServerAvailable();
      if (!isServerAvailable) {
        // Fallback al salvataggio semplice
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final trimmedVideoName = 'trimmed_video_$timestamp.mp4';
        final outputPath = path.join(tempDir.path, trimmedVideoName);
        await _simpleVideoSave(outputPath);
        return;
      }
      
      // Ottieni i punti di trim effettivi nel video
      final double startValue = _controller.minTrim;
      final double endValue = _controller.maxTrim;
      
      // Verifica se il trimming è necessario
      if (startValue == 0.0 && endValue == 1.0) {
        print('Nessun trimming necessario, salvo il video originale');
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final trimmedVideoName = 'trimmed_video_$timestamp.mp4';
        final outputPath = path.join(tempDir.path, trimmedVideoName);
        await _simpleVideoSave(outputPath);
        return;
      }
      
      // Calcola i tempi di trim
      final videoDuration = _controller.video.value.duration;
      final startTime = Duration(milliseconds: (startValue * videoDuration.inMilliseconds).round());
      final endTime = Duration(milliseconds: (endValue * videoDuration.inMilliseconds).round());
      
      // Genera il comando FFmpeg usando video_editor
      final config = VideoFFmpegVideoEditorConfig(_controller, name: 'trimmed_video');
      final execute = await config.getExecuteConfig();
      
      print('Comando FFmpeg generato: ${execute.command}');
      
      // Ferma il caricamento graduale e usa il progresso reale dal server
      _stopFakeProgress();
      
      // Usa il server per processare il video
      final processedFile = await VideoTrimmerService.trimVideo(
        videoFile: widget.videoFile,
        ffmpegCommand: execute.command,
        onProgress: (progress) {
          setState(() {
            // Mappa il progresso dal server (0-1) al range 80-100
            _trimProgress = 0.8 + (progress * 0.2);
          });
        },
      );
      
      if (processedFile != null) {
        setState(() {
          _isTrimming = false;
          _trimProgress = 1.0;
          _currentVideoFile = processedFile; // AGGIUNTO: aggiorna il file corrente
        });
        
        // Aggiorna il controller con il video trimmato
        _controller.dispose();
        _controller = VideoEditorController.file(
          processedFile,
          minDuration: const Duration(seconds: 1),
          maxDuration: const Duration(minutes: 120), // Aumentato a 2 ore per gestire video molto lunghi
        );
        _controller.initialize().then((_) {
          setState(() {});
          _controller.video.play();
        });
        

      } else {
        throw Exception('Nessun file processato ricevuto dal server');
      }
      
    } catch (e) {
      print('Errore durante il trimming del video: $e');
      setState(() {
        _isTrimming = false;
      });
      
      // Fallback al salvataggio semplice
      try {
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final trimmedVideoName = 'trimmed_video_$timestamp.mp4';
        final outputPath = path.join(tempDir.path, trimmedVideoName);
        await _simpleVideoSave(outputPath);
      } catch (fallbackError) {

      }
    }
  }
  
  // Formatta una durata nel formato "hh:mm:ss.ms" per i log
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    } else {
      return "$twoDigitMinutes:$twoDigitSeconds";
    }
  }
  
  // Metodo semplice per salvare il video come fallback
  Future<void> _simpleVideoSave(String outputPath) async {
    try {
      // Ferma il caricamento graduale
      _stopFakeProgress();
      
      // Copia il file originale nella posizione di output
      await widget.videoFile.copy(outputPath);
      final outputFile = File(outputPath);
      
      setState(() {
        _isTrimming = false;
        _trimProgress = 1.0;
        _currentVideoFile = outputFile; // AGGIUNTO: aggiorna il file corrente
        // Aggiorna il controller con il video originale
        _controller.dispose();
        _controller = VideoEditorController.file(
          outputFile,
          minDuration: const Duration(seconds: 1),
          maxDuration: const Duration(minutes: 120), // Aumentato a 2 ore per gestire video molto lunghi
        );
        _controller.initialize().then((_) {
          setState(() {});
          _controller.video.play();
        });
      });
      

    } catch (e) {
      setState(() {
        _isTrimming = false;
      });
    }
  }

  Future<void> _exportVideo() async {
    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });
    
    try {
      // Verifica se il server è disponibile
      final isServerAvailable = await VideoTrimmerService.isServerAvailable();
      if (!isServerAvailable) {
        // Fallback al salvataggio semplice
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final editedVideoName = 'edited_video_$timestamp.mp4';
        final outputPath = path.join(tempDir.path, editedVideoName);
        await _exportOriginalVideo(outputPath);
        return;
      }
      
      // Ottieni i punti di trim attuali
      final double startValue = _controller.minTrim;
      final double endValue = _controller.maxTrim;
      
      // Verifica se il trimming è necessario
      if (startValue == 0.0 && endValue == 1.0) {
        print('Nessun trimming necessario per l\'esportazione, salvo il video originale');
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final editedVideoName = 'edited_video_$timestamp.mp4';
        final outputPath = path.join(tempDir.path, editedVideoName);
        await _exportOriginalVideo(outputPath);
        return;
      }
      
      // Genera il comando FFmpeg usando video_editor
      final config = VideoFFmpegVideoEditorConfig(_controller, name: 'edited_video');
      final execute = await config.getExecuteConfig();
      
      print('Comando FFmpeg generato per export: ${execute.command}');
      
      // Usa il server per processare il video
      final processedFile = await VideoTrimmerService.trimVideo(
        videoFile: widget.videoFile,
        ffmpegCommand: execute.command,
        onProgress: (progress) {
          setState(() {
            _exportProgress = progress;
          });
        },
      );
      
      if (processedFile != null) {
        setState(() {
          _isExporting = false;
          _exportProgress = 1.0;
        });
        

        
        Navigator.pop(context, processedFile);
      } else {
        throw Exception('Nessun file processato ricevuto dal server');
      }
      
    } catch (e) {
      print('Errore durante l\'esportazione del video: $e');
      setState(() {
        _isExporting = false;
      });
      
      // Fallback al salvataggio semplice
      try {
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final editedVideoName = 'edited_video_$timestamp.mp4';
        final outputPath = path.join(tempDir.path, editedVideoName);
        await _exportOriginalVideo(outputPath);
      } catch (fallbackError) {
        // Fallback error handled silently
      }
    }
  }
  
  // Metodo per esportare il video originale senza modifiche
  Future<void> _exportOriginalVideo(String outputPath) async {
    try {
      // Copia il file originale nella posizione di output
      await widget.videoFile.copy(outputPath);
      final File outputFile = File(outputPath);
      
      setState(() {
        _isExporting = false;
        _exportProgress = 1.0;
      });
      
      // Return the original video file to upload page
      Navigator.pop(context, outputFile);
      

    } catch (e) {
      setState(() {
        _isExporting = false;
      });
    }
  }

  // Metodo per procedere al passaggio successivo senza trimming
  Future<void> _proceedToNext() async {
    try {
      // Salva il video corrente (originale o tagliato) in una posizione temporanea
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final videoName = 'video_$timestamp.mp4';
      final outputPath = path.join(tempDir.path, videoName);
      
      // Copia il file corrente nella posizione di output
      await _currentVideoFile.copy(outputPath);
      final File outputFile = File(outputPath);
      
      // Torna alla pagina precedente con il video corrente
      Navigator.pop(context, outputFile);
    } catch (e) {
      print('Errore durante il passaggio al video successivo: $e');
      // In caso di errore, torna comunque con il video corrente
      Navigator.pop(context, _currentVideoFile);
    }
  }

  // Metodo per avviare il caricamento graduale fino all'80%
  void _startFakeProgress() {
    _fakeProgressTimer?.cancel();
    double currentProgress = 0.0;
    
    _fakeProgressTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
      if (currentProgress < 0.8 && mounted) {
        // Caricamento molto veloce da 0 a 60%, poi più graduale fino a 80%
        double increment;
        if (currentProgress < 0.6) {
          // Molto veloce da 0 a 60%
          increment = 0.02 + (currentProgress * 0.03);
        } else {
          // Più graduale da 60 a 80%
          increment = 0.005 + ((currentProgress - 0.6) * 0.01);
        }
        
        currentProgress += increment;
        
        if (currentProgress > 0.8) {
          currentProgress = 0.8;
        }
        
        setState(() {
          _trimProgress = currentProgress;
        });
      } else {
        timer.cancel();
      }
    });
  }

  // Metodo per fermare il caricamento graduale
  void _stopFakeProgress() {
    _fakeProgressTimer?.cancel();
  }
} 