import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'scheduled_post_details_page.dart';
import './upload_video_page.dart'; // Add import for the upload page
import 'dart:io';
import 'dart:ui';

class MonthlyDetailPage extends StatefulWidget {
  final DateTime focusedMonth;
  final int selectedYear;
  final Map<DateTime, List<Map<String, dynamic>>> events;

  const MonthlyDetailPage({
    Key? key,
    required this.focusedMonth,
    required this.selectedYear,
    required this.events,
  }) : super(key: key);

  @override
  State<MonthlyDetailPage> createState() => _MonthlyDetailPageState();
}

class _MonthlyDetailPageState extends State<MonthlyDetailPage> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  bool _showExpandedEvents = false;
  List<Map<String, dynamic>> _selectedEvents = [];

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.focusedMonth;
    
    // Seleziona il primo giorno del mese che non è passato
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    if (widget.focusedMonth.month == now.month && widget.focusedMonth.year == now.year) {
      // Se il mese è quello corrente, seleziona oggi
      _selectedDay = today;
    } else {
      // Altrimenti seleziona il primo giorno del mese
      _selectedDay = DateTime(widget.focusedMonth.year, widget.focusedMonth.month, 1);
    }
    
    _selectedEvents = _getEventsForDay(_selectedDay);
  }

  // Get events for a specific day
  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final dateOnly = DateTime(day.year, day.month, day.day);
    final events = widget.events[dateOnly] ?? [];
    final now = DateTime.now();
    return events.where((event) {
      final scheduledTime = event['scheduledTime'] as int?;
      List<String> platforms = [];
      if (event['accounts'] != null && event['accounts'] is Map) {
        platforms = (event['accounts'] as Map).keys.map((e) => e.toString().toLowerCase()).toList();
      } else if (event['platforms'] != null && event['platforms'] is List) {
        platforms = (event['platforms'] as List).map((e) => e.toString().toLowerCase()).toList();
      } else if (event['platform'] != null) {
        platforms = [event['platform'].toString().toLowerCase()];
      }
      final isOnlyYouTube = platforms.length == 1 && platforms.first == 'youtube';
      final isPast = scheduledTime != null && scheduledTime < now.millisecondsSinceEpoch;
      if (isOnlyYouTube && isPast) return false;
      // Filtro già esistente: solo eventi futuri
      if (scheduledTime == null) return true;
      final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
      return scheduledDateTime.isAfter(now);
    }).toList();
  }

  // Check if a date is in the past (not including today)
  bool _isDateInPast(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final compareDate = DateTime(date.year, date.month, date.day);
    // Consider strictly past days (before today) as "past"
    return compareDate.isBefore(today);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final monthName = DateFormat('MMMM').format(_focusedDay);

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
      appBar: null, // Remove the AppBar since we'll use a custom header
        backgroundColor: theme.brightness == Brightness.dark 
            ? Color(0xFF121212) 
            : Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Custom header from about_page.dart
                _buildHeader(context),
                

                
                // Full month calendar
                Container(
                    height: MediaQuery.of(context).size.height * 0.5,
                  margin: const EdgeInsets.symmetric(horizontal: 16.0),
                  decoration: BoxDecoration(
                    // Effetto vetro semi-trasparente opaco
                    color: isDark 
                        ? Colors.white.withOpacity(0.15) 
                        : Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(20),
                    // Bordo con effetto vetro più sottile
                    border: Border.all(
                      color: isDark 
                          ? Colors.white.withOpacity(0.2)
                          : Colors.white.withOpacity(0.4),
                      width: 1,
                    ),
                    // Ombra per effetto profondità e vetro
                    boxShadow: [
                      BoxShadow(
                        color: isDark 
                            ? Colors.black.withOpacity(0.4)
                            : Colors.black.withOpacity(0.15),
                        blurRadius: isDark ? 25 : 20,
                        spreadRadius: isDark ? 1 : 0,
                        offset: const Offset(0, 10),
                      ),
                      // Ombra interna per effetto vetro
                      BoxShadow(
                        color: isDark 
                            ? Colors.white.withOpacity(0.1)
                            : Colors.white.withOpacity(0.6),
                        blurRadius: 2,
                        spreadRadius: -2,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    // Gradiente più sottile per effetto vetro
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
                  child: TableCalendar(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: _focusedDay,
                    calendarFormat: _calendarFormat,
                    enabledDayPredicate: (day) {
                      // Disabilita i giorni passati
                      return !_isDateInPast(day);
                    },
                    eventLoader: (day) {
                      final events = _getEventsForDay(day);
                      return events;
                    },
                    selectedDayPredicate: (day) {
                      return isSameDay(_selectedDay, day);
                    },
                    onDaySelected: (selectedDay, focusedDay) {
                      if (!_isDateInPast(selectedDay)) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                          _selectedEvents = _getEventsForDay(selectedDay);
                          _showExpandedEvents = true;
                        });
                      }
                    },
                    onPageChanged: (focusedDay) {
                      setState(() {
                        _focusedDay = focusedDay;
                      });
                    },
                    calendarStyle: CalendarStyle(
                      markersMaxCount: 3,
                      markerSize: 6,
                      markerDecoration: BoxDecoration(
                        color: const Color(0xFF667eea),
                        shape: BoxShape.circle,
                      ),
                      todayDecoration: BoxDecoration(
                        color: const Color(0xFF667eea).withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF667eea), // Colore iniziale: blu violaceo
                            Color(0xFF764ba2), // Colore finale: viola
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                        ),
                        shape: BoxShape.circle,
                      ),
                      outsideDaysVisible: false,
                      disabledTextStyle: TextStyle(
                        color: Colors.grey[300],
                        decoration: null,
                      ),
                      defaultTextStyle: TextStyle(
                        color: const Color(0xFF667eea),
                        fontWeight: FontWeight.w500,
                      ),
                      weekendTextStyle: TextStyle(
                        color: const Color(0xFF667eea),
                        fontWeight: FontWeight.w500,
                      ),
                      todayTextStyle: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      selectedTextStyle: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      formatButtonShowsNext: false,
                        titleTextStyle: TextStyle(
                          color: const Color(0xFF667eea),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        leftChevronIcon: Icon(Icons.chevron_left, color: const Color(0xFF667eea)),
                        rightChevronIcon: Icon(Icons.chevron_right, color: const Color(0xFF667eea)),
                      ),
                      daysOfWeekStyle: DaysOfWeekStyle(
                        weekdayStyle: TextStyle(
                          color: const Color(0xFF667eea),
                          fontWeight: FontWeight.bold,
                        ),
                        weekendStyle: TextStyle(
                          color: const Color(0xFF667eea),
                          fontWeight: FontWeight.bold,
                        ),
                    ),
                  ),
                ),
                
                // Empty space for expandable panel
                Expanded(child: Container()),
              ],
            ),
            
            // Expandable events panel
            _showExpandedEvents ? _buildExpandableEventsPanel() : Container(),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
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
                      Color(0xFF667eea), // Colore iniziale: blu violaceo
                      Color(0xFF764ba2), // Colore finale: viola
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
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
              // Badge specifico per la pagina
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Monthly View',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Build an expandable panel for events
  Widget _buildExpandableEventsPanel() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final events = _selectedEvents;
    
    // Calculate additional 7cm in logical pixels (approximately)
    // 1 cm ≈ 37.8 logical pixels
    final additionalHeight = 7 * 37.8; // Increased from 5cm to 7cm
    final maxHeightFraction = (MediaQuery.of(context).size.height * 0.9 + additionalHeight) / MediaQuery.of(context).size.height;
    
    // Ensure maxHeightFraction doesn't exceed 1.0
    final safeMaxHeightFraction = maxHeightFraction > 1.0 ? 0.98 : maxHeightFraction;
    
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      top: MediaQuery.of(context).size.height * 0.5, // Aggiornato da 0.4 a 0.5 per adattarsi alla nuova altezza del calendario
      child: DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: safeMaxHeightFraction, // Increased to add 7cm more in total
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? Color(0xFF121212) : Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      // Handle indicator
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 4),
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      
                      // Selected date header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.event,
                                color: isDark ? Color(0xFF667eea) : Color(0xFF667eea),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat('EEEE').format(_selectedDay),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  DateFormat('MMMM d, yyyy').format(_selectedDay),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${events.length} ${events.length == 1 ? 'post' : 'posts'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Color(0xFF667eea) : Color(0xFF667eea),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // New Post button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF667eea), // Colore iniziale: blu violaceo
                                Color(0xFF764ba2), // Colore finale: viola
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () => _createNewScheduledPost(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              minimumSize: Size(double.infinity, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            icon: Icon(Icons.add_circle_outline),
                            label: Text(
                              'Schedule New Post',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                      ),
                    ],
                  ),
                ),
                
                // Events list
                events.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.event_busy,
                                size: 64,
                                color: Color(0xFF667eea).withOpacity(0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No scheduled posts for this day',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final event = events[index];
                            return _buildEventListItem(event, theme);
                          },
                          childCount: events.length,
                        ),
                      ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Method to create a new scheduled post
  Future<void> _createNewScheduledPost(BuildContext context) async {
    final theme = Theme.of(context);
    
    // Show time picker with custom theme
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              dialHandColor: theme.colorScheme.primary.withOpacity(0.15),
              hourMinuteTextColor: theme.colorScheme.onSurface,
              dayPeriodTextColor: theme.colorScheme.onSurface,
              dialTextColor: theme.colorScheme.onSurface,
              dialBackgroundColor: theme.colorScheme.surfaceVariant,
              entryModeIconColor: theme.colorScheme.primary,
              hourMinuteShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              helpTextStyle: TextStyle(
                color: theme.colorScheme.onSurface,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            colorScheme: ColorScheme.light(
              primary: theme.colorScheme.primary.withOpacity(0.7),
              onPrimary: Colors.white,
              surface: theme.colorScheme.surface,
              onSurface: theme.colorScheme.onSurface,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (time != null && mounted) {
      // Create a DateTime object combining the selected day and time
      final scheduledDateTime = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        time.hour,
        time.minute,
      );
      
      // Navigate to the upload page with the scheduled date
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UploadVideoPage(
            scheduledDateTime: scheduledDateTime,
          ),
        ),
      );
    }
  }

  // Event list item for the expandable panel
  Widget _buildEventListItem(Map<String, dynamic> event, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    // DATA: Usa scheduledTime come nella sezione week di scheduled_posts_page.dart
    final scheduledTime = event['scheduledTime'] as int?;
    final dateTime = scheduledTime != null
        ? DateTime.fromMillisecondsSinceEpoch(scheduledTime)
        : null;
    final timeString = dateTime != null
        ? DateFormat('HH:mm').format(dateTime)
        : '';
    
    final title = event['title'] as String? ?? 'Scheduled Post';
    final description = event['description'] as String? ?? 'No description';
    
    // THUMBNAIL: Usa thumbnail_url come nel file 1.json
    final videoPath = event['media_url'] as String?; // Campo corretto per video
    final thumbnailPath = event['thumbnail_url'] as String?; // Campo principale per thumbnail
    final thumbnailCloudflareUrl = event['thumbnail_cloudflare_url'] as String?;
    
    // Determine the best thumbnail URL to use (priority: thumbnail_url > thumbnail_cloudflare_url)
    final String? bestThumbnailUrl = (thumbnailPath != null && thumbnailPath.isNotEmpty) 
        ? thumbnailPath 
        : (thumbnailCloudflareUrl != null && thumbnailCloudflareUrl.isNotEmpty) 
            ? thumbnailCloudflareUrl 
            : null;
    
    // SOCIAL MEDIA: Estrai piattaforme da accounts come nel file 1.json
    final accounts = event['accounts'] as Map<dynamic, dynamic>? ?? {};
    List<String> platforms = [];
    if (accounts.isNotEmpty) {
      platforms = accounts.keys.map((e) => e.toString()).toList();
    }
    
    // ACCOUNT COUNT: Conta account_display_name totali come in scheduled_posts_page.dart
    int accountCount = 0;
    if (accounts.isNotEmpty) {
      accounts.forEach((platform, platformData) {
        if (platformData is Map) {
          // Se è un oggetto con account_display_name, conta 1
          if (platformData.containsKey('account_display_name')) {
            accountCount += 1;
          } else {
            // Se è un oggetto con più account, conta le chiavi
            accountCount += platformData.length;
          }
        } else if (platformData is List) {
          accountCount += platformData.length;
        } else if (platformData != null) {
          accountCount += 1;
        }
      });
    }
    
    final accountText = accountCount > 0 
        ? '$accountCount ${accountCount == 1 ? 'account' : 'accounts'}'
        : 'No accounts';
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              // Effetto vetro semi-trasparente opaco
              color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.28),
              borderRadius: BorderRadius.circular(12),
              // Bordo con effetto vetro
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.4),
                width: 1,
              ),
              // Ombre per effetto sospeso
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black.withOpacity(0.35) : Colors.black.withOpacity(0.12),
                  blurRadius: isDark ? 22 : 18,
                  spreadRadius: isDark ? 0.5 : 0,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.55),
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
                        Colors.white.withOpacity(0.16),
                        Colors.white.withOpacity(0.08),
                      ]
                    : [
                        Colors.white.withOpacity(0.34),
                        Colors.white.withOpacity(0.24),
                      ],
              ),
            ),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ScheduledPostDetailsPage(
                      post: event,
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Thumbnail with improved styling
                Container(
          decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 150, // Aumentata larghezza
                      height: 110, // Aumentata altezza ulteriormente
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (bestThumbnailUrl != null)
                            _buildVideoPreview(
                              videoPath: videoPath,
                              thumbnailPath: thumbnailPath,
                              thumbnailUrl: null, // Non più usato
                              thumbnailCloudflareUrl: thumbnailCloudflareUrl,
                              bestThumbnailUrl: bestThumbnailUrl,
                              width: 150,
                              height: 110,
                              isImage: event['media_type'] == 'image',
                            )
                          else if (videoPath?.isNotEmpty == true)
                            _buildVideoPreview(
                              videoPath: videoPath,
                              thumbnailPath: thumbnailPath,
                              thumbnailUrl: null, // Non più usato
                              thumbnailCloudflareUrl: thumbnailCloudflareUrl,
                              bestThumbnailUrl: null,
                              width: 150,
                              height: 110,
                              isImage: event['media_type'] == 'image',
                            )
                                                      else
                              Container(
                                color: Colors.grey[200],
                                child: Center(
                                  child: Icon(
                                    event['media_type'] == 'image' ? Icons.image : Icons.video_library,
                                    size: 28,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              ),
                          // Duration indicator - use static duration display
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: _buildStaticDurationBadge(event),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // Video details
                Expanded(
                  child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
            children: [
                      // Platform logos row
                      if (platforms.isNotEmpty)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width - 210, // Adjust for thumbnail and padding
                          ),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.transparent : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Wrap(
                              spacing: 8, // Slightly reduce spacing
                              runSpacing: 6, // Vertical spacing between rows
                              alignment: WrapAlignment.start,
                              children: [
                                // Limit to maximum 5 platforms (4 icons + "+X" indicator)
                                if (platforms.length <= 5)
                                  ...platforms.map((platform) => _buildPlatformLogo(platform.toString()))
                                else
                                  ...[
                                    ...platforms.take(4).map((platform) => _buildPlatformLogo(platform.toString())),
              Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: [
                                          BoxShadow(
                                            color: theme.colorScheme.primary.withOpacity(0.1),
                                            blurRadius: 2,
                                            offset: Offset(0, 1),
                                          ),
                                        ],
                                      ),
                child: Text(
                                        '+${platforms.length - 4}',
                  style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                              ],
                  ),
                ),
              ),
              
                      // Spazio maggiore prima delle informazioni di account e data
                      const SizedBox(height: 15),
                      
                      // Account info senza status badge
                      Container(
                        padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                  children: [
                                                                                    Icon(
                            Icons.people,
                            size: 14,
                            color: isDark ? Color(0xFF667eea) : Color(0xFF667eea),
                          ),
                            const SizedBox(width: 4),
                    Text(
                                                            accountText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Color(0xFF667eea) : Color(0xFF667eea),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Piccolo spazio tra account e data
                      const SizedBox(height: 5),
                      
                      // Timestamp con status badge allineato a destra
                    Row(
                      children: [
                          // Timestamp a sinistra
                          Expanded(
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            decoration: BoxDecoration(
                                color: isDark ? Colors.transparent : Colors.grey[100],
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 2,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.schedule,
                                    size: 14,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                              child: Text(
                                      timeString,
                                style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(width: 8),
                          
                          // Status badge allineato a destra nella stessa riga della data
                          _buildScheduledStatusChip(),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper method to build platform logos from assets
  Widget _buildPlatformLogo(String platform) {
    String logoPath;
    double size = 24; // Slightly smaller size
    
    switch (platform.toLowerCase()) {
      case 'youtube':
        logoPath = 'assets/loghi/logo_yt.png';
        break;
      case 'tiktok':
        logoPath = 'assets/loghi/logo_tiktok.png';
        break;
      case 'instagram':
        logoPath = 'assets/loghi/logo_insta.png';
        break;
      case 'facebook':
        logoPath = 'assets/loghi/logo_facebook.png';
        break;
      case 'twitter':
        logoPath = 'assets/loghi/logo_twitter.png';
        break;
      case 'threads':
        logoPath = 'assets/loghi/threads_logo.png';
        break;
      default:
        // Fallback to icon-based display if logo not available
        return _buildPlatformIcon(platform);
    }
    
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        logoPath,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) {
          // Fallback to icon if image fails to load
          print('Error loading platform logo: $error');
          return _buildPlatformIcon(platform);
        },
      ),
    );
  }
  
  // Widget per lo stato "Scheduled"
  Widget _buildScheduledStatusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9500), // Arancione per scheduled
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF9500).withOpacity(0.3),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: 8,
            color: Colors.white,
          ),
          const SizedBox(width: 3),
          Text(
            'SCHEDULED',
            style: TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
  
  // Nuovo metodo per mostrare la durata in modo statico
  Widget _buildStaticDurationBadge(Map<String, dynamic> event) {
    // Controlla se è un carosello (ha cloudflare_urls o media_urls con più di una voce)
    final cloudflareUrls = event['cloudflare_urls'];
    final mediaUrls = event['media_urls'];
    
    // Helper per verificare se una struttura contiene più elementi
    bool _hasMultipleItems(dynamic data) {
      if (data == null) return false;
      if (data is List && data.length > 1) return true;
      if (data is Map) {
        // Conta solo le chiavi che sono numeriche o stringhe numeriche (indici)
        int count = 0;
        for (var key in data.keys) {
          // Accetta chiavi numeriche (int) o stringhe numeriche ("0", "1", "2", ecc.)
          if (key is int || (key is String && int.tryParse(key) != null)) {
            count++;
          }
        }
        return count > 1;
      }
      return false;
    }
    
    // Verifica se è un carosello controllando entrambi i campi
    bool isCarousel = _hasMultipleItems(cloudflareUrls) || _hasMultipleItems(mediaUrls);
    
    // Se è un carosello, mostra "CAROUSEL" (ha priorità su tutto)
    if (isCarousel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'CAROUSEL',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    // Se è un'immagine, mostra "IMG"
    if (event['media_type'] == 'image') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'IMG',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    
    // Per i video, usa la vera durata dal database se disponibile
    String duration;
    final durationSeconds = event['video_duration_seconds'] as int?;
    final durationMinutes = event['video_duration_minutes'] as int?;
    final durationRemainingSeconds = event['video_duration_remaining_seconds'] as int?;
    if (durationSeconds != null && durationMinutes != null && durationRemainingSeconds != null) {
      duration = '$durationMinutes:${durationRemainingSeconds.toString().padLeft(2, '0')}';
    } else {
      // Fallback: usa una durata basata sull'ID del video (per compatibilità con video esistenti)
      final idString = event['id'] as String? ?? '';
      final hashCode = idString.hashCode.abs() % 300 + 30; // tra 30 e 329 secondi
      final minutes = hashCode ~/ 60;
      final seconds = hashCode % 60;
      duration = '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        duration,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
  
  // Helper method per visualizzare l'anteprima video
  Widget _buildVideoPreview({
    required String? videoPath,
    String? thumbnailPath,
    String? thumbnailUrl,
    String? thumbnailCloudflareUrl,
    String? bestThumbnailUrl,
    double width = 150,
    double height = 110,
    bool isImage = false,
  }) {
    // Se è un'immagine, gestiscila come in scheduled_posts_page.dart
    if (isImage) {
      // Per le immagini, usa bestThumbnailUrl se disponibile
      if (bestThumbnailUrl != null && bestThumbnailUrl.isNotEmpty) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              bestThumbnailUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                print('Error loading best thumbnail: $error');
                return _buildImagePlaceholder();
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return _buildLoadingPlaceholder();
              },
            ),
            _buildGradientOverlay(),
          ],
        );
      }
      
      // Fallback: prova videoPath se è un URL
      if (videoPath != null && videoPath.isNotEmpty && 
          (videoPath.startsWith('http://') || videoPath.startsWith('https://'))) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              videoPath,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                print('Error loading image from videoPath: $error');
                return _buildImagePlaceholder();
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return _buildLoadingPlaceholder();
              },
            ),
            _buildGradientOverlay(),
          ],
        );
      }
      
      // Fallback: prova thumbnailCloudflareUrl
      if (thumbnailCloudflareUrl != null && thumbnailCloudflareUrl.isNotEmpty) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              thumbnailCloudflareUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                print('Error loading Cloudflare image: $error');
                return _buildImagePlaceholder();
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return _buildLoadingPlaceholder();
              },
            ),
            _buildGradientOverlay(),
          ],
        );
      }
      
      // Se tutto fallisce, mostra placeholder per immagine
      return _buildImagePlaceholder();
    }
    
    // Per i video, usa la stessa logica di scheduled_posts_page.dart
    // Se abbiamo una bestThumbnailUrl, usala direttamente
    if (bestThumbnailUrl != null && bestThumbnailUrl.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            bestThumbnailUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              print('Error loading best thumbnail: $error');
              return _buildVideoPlaceholder();
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildLoadingPlaceholder();
            },
          ),
          _buildGradientOverlay(),
        ],
      );
    }
    
    // Fallback: prova thumbnailCloudflareUrl
    if (thumbnailCloudflareUrl != null && thumbnailCloudflareUrl.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            thumbnailCloudflareUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              print('Error loading Cloudflare thumbnail: $error');
              return _buildVideoPlaceholder();
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildLoadingPlaceholder();
            },
          ),
          _buildGradientOverlay(),
        ],
      );
    }
    
    // Fallback: prova thumbnailPath se è un URL
    if (thumbnailPath != null && thumbnailPath.isNotEmpty && 
        (thumbnailPath.startsWith('http://') || thumbnailPath.startsWith('https://'))) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            thumbnailPath,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              print('Error loading thumbnail from path: $error');
              return _buildVideoPlaceholder();
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildLoadingPlaceholder();
            },
          ),
          _buildGradientOverlay(),
        ],
      );
    }
    
    // Se tutto fallisce, mostra placeholder per video
    return _buildVideoPlaceholder();
  }
  
  // Placeholder specifico per le immagini
  Widget _buildImagePlaceholder() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: Colors.grey[200],
          child: Center(
            child: Icon(
              Icons.image,
              color: Colors.grey[400],
              size: 32,
            ),
          ),
        ),
        _buildGradientOverlay(),
      ],
    );
  }
  
  // Placeholder specifico per i video
  Widget _buildVideoPlaceholder() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: Colors.grey[200],
          child: Center(
            child: Icon(
              Icons.video_library,
              color: Colors.grey[400],
              size: 32,
            ),
          ),
        ),
        _buildGradientOverlay(),
      ],
    );
  }
  
  Widget _buildGradientOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.5),
          ],
          stops: const [0.6, 1.0],
        ),
      ),
    );
  }
  
  Widget _buildLoadingPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
          ),
        ),
      ),
    );
  }
  
  // Helper method per creare icone di piattaforma come fallback
  Widget _buildPlatformIcon(String platform) {
    IconData iconData;
    Color iconColor;
    
    switch (platform.toLowerCase()) {
      case 'youtube':
        iconData = Icons.play_circle_filled;
        iconColor = Colors.red;
        break;
      case 'tiktok':
        iconData = Icons.music_note;
        iconColor = Colors.black87;
        break;
      case 'instagram':
        iconData = Icons.camera_alt;
        iconColor = Colors.purple;
        break;
      case 'facebook':
        iconData = Icons.facebook;
        iconColor = Colors.blue;
        break;
      case 'twitter':
        iconData = Icons.chat_bubble;
        iconColor = Colors.lightBlue;
        break;
      case 'threads':
        iconData = Icons.tag;
        iconColor = Colors.black87;
        break;
      case 'snapchat':
        iconData = Icons.photo_camera;
        iconColor = Colors.amber;
        break;
      case 'linkedin':
        iconData = Icons.work;
        iconColor = Colors.blue.shade800;
        break;
      case 'pinterest':
        iconData = Icons.push_pin;
        iconColor = Colors.red.shade700;
        break;
      default:
        iconData = Icons.public;
        iconColor = Colors.grey;
    }
    
    return Container(
      width: 24, // Match the logo size
      height: 24, // Match the logo size
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconData,
        size: 14,
        color: iconColor,
      ),
    );
  }
} 