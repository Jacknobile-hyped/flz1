import 'package:flutter/material.dart';
import 'contact_support_page.dart';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter

class TroubleshootingPage extends StatefulWidget {
  const TroubleshootingPage({super.key});

  @override
  State<TroubleshootingPage> createState() => _TroubleshootingPageState();
}

class _TroubleshootingPageState extends State<TroubleshootingPage> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Map<String, bool> _expandedItems = {};
  
  // Topic dropdown variables
  bool _showTopicDropdown = false;
  late AnimationController _topicAnimationController;
  late Animation<double> _topicAnimation;
  String _selectedTopic = 'All Topics';

  // Social platform logo mapping
  final Map<String, String> _platformLogos = {
    'Instagram': 'assets/loghi/logo_insta.png',
    'Facebook': 'assets/loghi/logo_facebook.png',
    'YouTube': 'assets/loghi/logo_yt.png',
    'TikTok': 'assets/loghi/logo_tiktok.png',
    'Twitter': 'assets/loghi/logo_twitter.png',
    'Threads': 'assets/loghi/threads_logo.png',
  };

  final List<Map<String, dynamic>> _allIssues = [
    {
      'section': 'General App Issues',
      'items': [
        {
          'title': 'App Won\'t Open or Crashes',
          'solution': 'If the app doesn\'t open or crashes at startup:\n\n'
              '1. Make sure you have the latest version installed\n'
              '2. Restart your device\n'
              '3. Free up device storage space\n'
              '4. Clear the app cache (Settings > Apps > Fluzar > Storage > Clear Cache)',
          'icon': Icons.phonelink_erase,
        },
        {
          'title': 'App is Slow or Freezing',
          'solution': 'If the app is running slowly or freezing:\n\n'
              '1. Close background apps to free up memory\n'
              '2. Check your internet connection speed (minimum 5Mbps recommended)\n'
              '3. Clear app cache and temporary files\n'
              '4. Restart your device\n'
              '5. Make sure you\'re using the latest app version\n'
              '6. If you\'re on a cellular connection, try connecting to WiFi instead',
          'icon': Icons.speed,
        },
        {
          'title': 'Data Not Loading',
          'solution': 'If your data or analytics aren\'t loading:\n\n'
              '1. Check your internet connection\n'
              '2. Pull down to refresh the screen\n'
              '3. Verify if the specific social platform is experiencing downtime\n'
              '4. Log out and log back in to refresh your authentication tokens\n'
              '5. Clear app cache\n'
              '6. Try disabling any VPN or proxy you might be using',
          'icon': Icons.data_usage,
        },
      ],
    },
    {
      'section': 'Authentication Issues',
      'items': [
        {
          'title': 'Registration Problems',
          'solution': 'If you can\'t register:\n\n'
              '1. Verify you have a stable internet connection\n'
              '2. Check if the email is already registered (try password recovery instead)\n'
              '3. Use a valid email and password (min. 6 characters, including a number and symbol)\n'
              '4. Make sure you\'re using a properly formatted email address\n'
              '5. If using social login, ensure your social accounts are active\n'
              '6. Try an alternative email provider if problems persist',
          'icon': Icons.app_registration,
        },
        {
          'title': 'Forgot Password',
          'solution': 'To reset your password:\n\n'
              '1. Click "Forgot Password?" on the login screen\n'
              '2. Enter the email address associated with your account\n'
              '3. Check all mailboxes (including spam/promotions folder) for the reset email\n'
              '4. The link in the email expires after 24 hours, so use it promptly\n'
              '5. If not received within 5 minutes, try the "Resend" option\n'
              '6. If the reset fails, contact support with your account email',
          'icon': Icons.lock_reset,
        },
        {
          'title': 'No Confirmation Email',
          'solution': 'If you haven\'t received the confirmation email:\n\n'
              '1. Check spam, promotions, and updates folders\n'
              '2. Verify you entered the email correctly during registration\n'
              '3. Add noreply@fluzar.com to your contacts or safe senders list\n'
              '4. Wait at least 15 minutes as email delivery can be delayed\n'
              '5. Try requesting a new confirmation email after 5 minutes\n'
              '6. If using a business or institutional email, check with your IT department if they block automated emails',
          'icon': Icons.mark_email_unread,
        },
        {
          'title': 'Login Session Expired',
          'solution': 'If you\'re frequently logged out or see "session expired":\n\n'
              '1. Check if you\'re using Fluzar on multiple devices\n'
              '2. Make sure your device time and date are set correctly\n'
              '3. Check if your account has been accessed from an unusual location (you may receive an email about this)\n'
              '4. Try changing your password if you suspect unauthorized access',
          'icon': Icons.timer_off,
        },
      ],
    },
    {
      'section': 'Social Media Connection',
      'items': [
        {
          'title': 'Instagram Connection Issues',
          'solution': 'If you can\'t connect Instagram:\n\n'
              '1. Ensure you have an Instagram Business or Creator account (Personal accounts won\'t work)\n'
              '2. Verify it\'s linked to a Facebook Page (required for analytics access)\n'
              '3. Check all permissions are enabled during the connection process\n'
              '4. Make sure you\'re using the account owner credentials (not a page manager)\n'
              '5. Try disconnecting and reconnecting the account\n'
              '6. Verify you\'re not exceeding Instagram\'s limits (max 25 posts per 24 hours)',
          'icon': Icons.camera_alt,
        },
        {
          'title': 'Facebook Connection Issues',
          'solution': 'If Facebook won\'t connect:\n\n'
              '1. Verify you have a professional or creator profile\n'
              '2. Login with correct admin credentials (you must be an admin of the page)\n'
              '3. Accept all required permissions during the authorization flow\n'
              '4. Check if your Facebook account is in good standing (not restricted)\n'
              '5. Ensure the Facebook page is published and not in a restricted category\n'
              '6. Try using a different browser or device for the connection process\n'
              '7. Facebook periodically requires re-authentication - you may need to reconnect every 60 days',
          'icon': Icons.facebook,
        },
        {
          'title': 'YouTube Connection Issues',
          'solution': 'If YouTube won\'t connect:\n\n'
              '1. Ensure you have an active YouTube channel\n'
              '2. Verify Google authentication is properly authorized\n'
              '3. Complete 2FA if enabled on your Google account\n'
              '4. Make sure you have proper ownership rights to the channel\n'
              '5. Check if your channel has any community guideline strikes\n'
              '6. YouTube requires specific scopes - ensure you approved all permissions during setup\n'
              '7. If you recently changed your Google account password, you\'ll need to reconnect',
          'icon': Icons.play_circle,
        },
        {
          'title': 'TikTok Connection',
          'solution': 'If TikTok won\'t connect:\n\n'
              '1. Ensure you have a business account (creator accounts for TikTok)\n'
              '2. Accept all app permissions during the connection flow\n'
              '3. For TikTok, verify your account isn\'t set to private',
          'icon': Icons.video_library,
        },
        {
          'title': 'Twitter (X) Connection Problems',
          'solution': 'If Twitter/X won\'t connect or shows errors:\n\n'
              '1. Ensure your Twitter/X account has a verified email address\n'
              '2. Check if your account is in good standing (not restricted or limited)\n'
              '3. For business accounts, ensure your developer account is properly set up\n'
              '4. Try logging out of Twitter on all devices, then reconnecting\n'
              '5. If you recently changed your username, disconnect and reconnect your account',
          'icon': Icons.flutter_dash,
        },
        {
          'title': 'Facebook Access Token Invalid After Password Change',
          'solution': 'If you change your Facebook password after connecting your account to Fluzar, Facebook will automatically invalidate the access token for security reasons.\n\nTo continue using Facebook features in Fluzar, you must log in again and reconnect your Facebook account. This will generate a new valid access token.\n\nImportant: If you have Instagram accounts connected to that Facebook Page, you must also disconnect and reconnect those Instagram accounts. Likewise, if you have Threads accounts connected to those Instagram accounts (which are in turn linked to the Facebook Page), you will need to reconnect those Threads accounts as well.\n\nIf you see errors or are unable to publish to Facebook, Instagram, or Threads after a password change, simply disconnect and reconnect each affected account. This will restore full functionality without losing any data.',
          'icon': Icons.facebook,
        },
        {
          'title': 'The Access Token is Invalid',
          'solution': 'If you see an error that your access token is invalid or expired, this means the connection between Fluzar and your social account has been interrupted (often due to password changes, security updates, or token expiration). To resolve this, simply disconnect and reconnect the problematic account from the Fluzar app. This will generate a new valid access token and restore full functionality. You will not lose any data by reconnecting.',
          'icon': Icons.vpn_key,
        },
        {
          'title': 'Connecting Multiple Facebook Profiles',
          'solution': 'To connect a different Facebook profile to Fluzar:\n\n'
              '1. First, log out of Facebook completely on your device\n'
              '2. Close the Facebook app or browser completely\n'
              '3. In Fluzar, go to the Facebook connection page\n'
              '4. Tap "Connect Account" or "Add Account"\n'
              '5. You will be redirected to Facebook login\n'
              '6. Log in with the Facebook account you want to connect\n'
              '7. Accept all required permissions when prompted\n'
              '8. The new Facebook profile will now be connected to Fluzar\n\n'
              'Note: You can connect multiple Facebook profiles, but you must log out of Facebook completely before connecting each new profile to avoid authentication conflicts.',
          'icon': Icons.facebook,
        },
        {
          'title': 'YouTube Daily Upload Limits',
          'solution': 'YouTube has specific daily upload limits for accounts:\n\n'
              'During upload, if YouTube displays the error “Daily upload limit reached,” it means that the channel has reached the maximum number of videos that can be uploaded in the last 24 hours. This limit is automatically imposed by YouTube to prevent abuse or suspicious activity and may vary depending on the age of the channel, its history, and the region.\n\n'
              'Important notes:\n'
              '• These limits apply to all uploads, including scheduled posts\n'
              '• The limit resets at midnight Pacific Time (PST/PDT)\n'
              '• If you reach the daily limit, you\'ll need to wait until the next day\n'
              '• These limits are set by YouTube and cannot be changed by Fluzar\n'
              '• Consider using multiple YouTube accounts if you need to upload more content daily',
          'icon': Icons.play_circle,
        },
      ],
    },
    {
      'section': 'Video Upload & Publishing',
      'items': [
        {
          'title': 'Video Upload Issues',
          'solution': 'If you can\'t upload a video:\n\n'
              '1. Check if file format is supported\n'
              '2. Ensure video length meets platform limits\n'
              '3. File size shouldn\'t exceed 500MB for optimal performance\n'
              '4. Verify you have a stable internet connection (WiFi recommended for large uploads)\n'
              '5. Check available storage on your device\n'
              '6. Try compressing the video to a smaller size if it\'s very large\n'
              '7. If using cellular data, check if your plan restricts large uploads',
          'icon': Icons.upload_file,
        },
        {
          'title': 'Publishing Problems',
          'solution': 'If video uploads but won\'t publish:\n\n'
              '1. Verify at least one social platform is selected and properly connected\n'
              '2. Check if account authentication is still valid (tokens expire after a period)\n'
              '3. Ensure publishing permissions are active for each platform\n'
              '4. Verify the content meets platform guidelines (check for restricted content)\n'
              '5. Some platforms have daily publishing limits - you may have exceeded them\n'
              '6. Check your scheduled time isn\'t in the past\n'
              '7. If publishing to Instagram, ensure your caption doesn\'t have too many hashtags',
          'icon': Icons.publish,
        },
        {
          'title': 'Poor Video Quality',
          'solution': 'If published video quality is low:\n\n'
              '1. Upload videos with minimum 720p resolution (1080p recommended)\n'
              '2. Avoid over-compressing before upload (use "high quality" export settings)\n'
              '3. Use WiFi to avoid mobile data compression\n'
              '4. Check if "Preserve Original Quality" is enabled in app settings\n'
              '5. Some platforms automatically compress videos regardless of upload quality\n'
              '6. Ensure proper lighting and stable camera during recording\n'
              '7. Videos with fast motion require higher bitrate - adjust export settings accordingly',
          'icon': Icons.high_quality,
        },
        {
          'title': 'Caption/Hashtag Issues',
          'solution': 'If captions or hashtags aren\'t appearing correctly:\n\n'
              '1. Check character limits for each platform (they vary significantly)\n'
              '2. Avoid special characters that may not be supported\n'
              '3. Instagram limits hashtags to 30 per post\n'
              '4. Twitter has a 280 character limit for unverified accounts, 25,000 for verified accounts\n'
              '5. Some platforms automatically strip certain hashtags (if flagged/restricted)\n'
              '6. Try placing hashtags in the comments instead of caption for Instagram\n'
              '7. Avoid using the same set of hashtags repeatedly as they may be flagged as spam',
          'icon': Icons.tag,
        },
        {
          'title': 'Failed Scheduled Posts',
          'solution': 'If scheduled posts aren\'t publishing:\n\n'
              '1. Verify platform connection hasn\'t expired (re-authenticate if needed)\n'
              '2. Make sure your account is in good standing (not restricted)\n'
              '3. Check if you\'ve exceeded daily posting limits for the platform\n'
              '4. It may take up to 5 minutes for all videos to be published and saved in your Fluzar account history.',
          'icon': Icons.schedule_send,
        },
      ],
    },
    {
      'section': 'Account & Dashboard Management',
      'items': [
        {
          'title': 'Missing Connected Accounts',
          'solution': 'If you can\'t see connected accounts:\n\n'
              '1. Pull down to refresh the screen\n'
              '2. Check if account was removed/disconnected (platforms may disconnect after 60-90 days)\n'
              '3. Try reconnecting manually\n'
              '4. Verify you\'re using the same Fluzar account where connections were made\n'
              '5. Log out and log back in to refresh your account state',
          'icon': Icons.account_circle_outlined,
        },
        {
          'title': 'Video History Not Updating',
          'solution': 'If video history isn\'t updating:\n\n'
              '1. Reload the app\n'
              '2. Verify you\'re logged in to the correct account\n'
              '3. Check if video was actually published (view the platform directly)\n'
              '4. Wait 5-10 minutes as history updates aren\'t always instant\n'
              '5. Ensure your device time and date are set correctly\n'
              '6. Try clearing app cache\n'
              '7. Some platforms have delayed reporting API - data may take up to 24 hours to appear',
          'icon': Icons.history,
        },
        {
          'title': 'Multiple Device Usage',
          'solution': 'If having issues using multiple devices:\n\n'
              '1. Verify you\'re using the same account on all devices\n'
              '2. Be aware some features may not sync instantly between devices\n'
              '3. Ensure all devices are running the same version of the app\n'
              '4. Premium features are account-bound, not device-bound',
          'icon': Icons.devices,
        },
        {
          'title': 'Analytics Not Accurate',
          'solution': 'If analytics seem incorrect or not updating:\n\n'
              '1. Analytics typically have a 24-48 hour delay from platforms\n'
              '2. Verify account connections are still valid\n'
              '3. Some metrics are only available for business/premium accounts\n'
              '4. Each platform calculates metrics differently (view definitions in help)\n'
              '5. Historical data older than 30 days may be aggregated or summarized',
          'icon': Icons.analytics,
        },
        {
          'title': 'Subscription Issues',
          'solution': 'If experiencing subscription or billing problems:\n\n'
              '1. Verify your payment method is valid and hasn\'t expired\n'
              '2. Check if payment was actually processed (bank statement)\n'
              '3. Free trial users: check remaining trial period\n'
              '4. Subscription status updates may take up to 24 hours to reflect\n'
              '5. If downgrading, features will be immediately and automatically deactivated\n'
              '6. Contact your payment provider if charges appear but subscription isn\'t active\n'
              '7. For refund requests, contact support with your order number',
          'icon': Icons.payment,
        },
        {
          'title': 'Profile Picture Not Updating',
          'solution': 'If your social media profile picture isn\'t updating in Fluzar:\n\n'
              '1. For security reasons, Fluzar cannot automatically access your social accounts\n'
              '2. When you connect an account, Fluzar saves a secure copy of your profile picture\n'
              '3. If you change your profile picture on the social platform, it won\'t update in Fluzar automatically\n'
              '4. To see your new profile picture in Fluzar, you need to reconnect that social account\n'
              '5. Go to the social platform page in Fluzar and tap "Reconnect" or "Update Account"\n'
              '6. This will trigger a new authentication and download your updated profile picture\n'
              '7. This is a security feature to protect your privacy - Fluzar only updates data when you explicitly authorize it',
          'icon': Icons.account_circle,
        },
        {
          'title': 'TikTok Username Not Displaying',
          'solution':               'If your TikTok username is not showing correctly in Fluzar:\n\n'
              '1. This is a known limitation of TikTok\'s service\n'
              '2. TikTok does not provide username information\n'
              '3. This affects all third-party apps, not just Fluzar\n'
              '4. Your TikTok account is still properly connected and functional\n'
              '5. You can still upload and schedule content to TikTok normally\n'
              '6. The username display issue does not affect posting functionality\n'
              '7. This is a platform limitation, not a Fluzar bug or error',
          'icon': Icons.person_off,
        },
        {
          'title': 'Profile Likes & Comments Not Updating',
          'solution': 'If your profile statistics (likes and comments) are not updating or showing incorrect numbers:\n\n'
              '1. Profile statistics only include data from videos published through Fluzar\n'
              '2. Videos uploaded directly to social platforms (without using Fluzar) are not counted\n'
              '3. To update statistics for published videos, you must manually refresh the data\n'
              '4. Go to your published video details page and tap "View Analytics"\n'
              '5. This will fetch the latest likes and comments data from the social platform\n'
              '6. The profile totals will automatically update after refreshing each video\'s analytics\n'
              '7. Statistics may take 24-48 hours to appear on social platforms after publishing\n'
              '8. Some platforms have API limitations that may delay data updates\n'
              '9. Free accounts have limited analytics refresh rate (manual refresh required)',
          'icon': Icons.analytics_outlined,
        },
      ],
    },
    {
      'section': 'Notifications & Suggestions',
      'items': [
        {
          'title': 'Missing Notifications',
          'solution': 'If not receiving scheduled posts notifications:\n\n'
              '1. Enable notifications in phone settings (System Settings > Apps > Fluzar > Notifications)\n'
              '2. Verify app notification settings are enabled in the Fluzar settings menu\n'
              '3. Update to the latest app version\n'
              '4. Check if your device has "Do Not Disturb" or Focus mode enabled\n'
              '5. Some Android devices have aggressive battery optimizations that block notifications\n'
              '6. Try reinstalling the app if other solutions don\'t work\n'
              '7. For iOS, ensure Background App Refresh is enabled for Fluzar',
          'icon': Icons.notifications_active,
        },
      ],
    },
    {
      'section': 'Performance & Optimization',
      'items': [
        {
          'title': 'Video Optimization Failed',
          'solution': 'If video optimization isn\'t working properly:\n\n'
              '1. Check if your device has sufficient processing power\n'
              '2. Ensure enough free storage space\n'
              '3. Some video formats may not be compatible with optimization\n'
              '4. Very large files (>1GB) may timeout during processing\n'
              '5. Try using suggested export settings',
          'icon': Icons.movie_filter,
        },
        {
          'title': 'Cross-Platform Content Issues',
          'solution': 'If cross-platform content adaptation isn\'t working:\n\n'
              '1. Each platform has different aspect ratio requirements\n'
              '2. Ensure the original video has sufficient resolution for cropping\n'
              '3. Some content types can\'t be automatically adapted (e.g., text-heavy videos)\n'
              '4. Manual adjustments may be needed for optimal results\n'
              '5. Check platform-specific requirements\n'
              '6. Use the preview function to verify before posting',
          'icon': Icons.devices_other,
        },
        {
          'title': 'Thumbnail Generation Problems',
          'solution': 'If auto-thumbnail generation isn\'t working:\n\n'
              '1. Ensure video has processed completely\n'
              '2. Check if video format is supported (MP4, MOV recommended)\n'
              '3. Some very short videos (<3 seconds) may have limited thumbnail options\n'
              '4. Manual thumbnail upload is always available as an alternative\n'
              '5. Recommended thumbnail size: 1280x720px (16:9 aspect ratio)\n'
              '6. For best results, use high contrast scenes from your video',
          'icon': Icons.image,
        },
      ],
    },
  ];

  List<Map<String, dynamic>> get _filteredIssues {
    List<Map<String, dynamic>> filteredByTopic = _allIssues;
    
    // Filter by topic if not "All Topics"
    if (_selectedTopic != 'All Topics') {
      filteredByTopic = _allIssues.where((section) {
        return section['section'] == _selectedTopic;
      }).toList();
    }
    
    // Filter by search query
    if (_searchQuery.isEmpty) {
      return filteredByTopic;
    }

    final query = _searchQuery.toLowerCase();
    return filteredByTopic.map((section) {
      final filteredItems = (section['items'] as List).where((item) {
        final title = (item['title'] as String).toLowerCase();
        final solution = (item['solution'] as String).toLowerCase();
        return title.contains(query) || solution.contains(query);
      }).toList();

      if (filteredItems.isEmpty) {
        return null;
      }

      return {
        'section': section['section'],
        'items': filteredItems,
      };
    }).whereType<Map<String, dynamic>>().toList();
  }

  @override
  void initState() {
    super.initState();
    
    // Initialize topic dropdown animation
    _topicAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _topicAnimation = CurvedAnimation(
      parent: _topicAnimationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _topicAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      appBar: null,
      body: Stack(
        children: [
          // Main content area - no padding, content can scroll behind floating elements
          SafeArea(
            child: _filteredIssues.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: theme.colorScheme.primary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No results found',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.primary.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try different keywords',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 6,
                    radius: const Radius.circular(10),
                    child: ListView(
                                          padding: EdgeInsets.only(
                      top: 80 + MediaQuery.of(context).size.height * 0.06, // Reduced to move dropdown higher
                      left: 20, 
                      right: 20, 
                      bottom: 10
                    ), // Add top padding for floating elements
                                          children: [
                      _buildTopicDropdown(),
                      SizedBox(height: 30), // Increased padding below dropdown
                      ..._filteredIssues.expand((section) => [
                            _buildIssueSection(
                              theme,
                              section['section'] as String,
                              _buildSectionItems(
                                theme, 
                                section['section'] as String,
                                section['items'] as List,
                              ),
                            ),
                            const SizedBox(height: 24),
                          ]),
                      _buildContactSupport(theme),
                    ],
                    ),
                  ),
          ),
          
          // Floating header with search bar
          Positioned(
            top: MediaQuery.of(context).size.height * 0.13, // 9% + 5% = 14% dell'altezza dello schermo
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search bar with glass effect
                  ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        height: 42,
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
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search for solutions...',
                            hintStyle: TextStyle(
                              color: theme.hintColor,
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: theme.colorScheme.primary,
                              size: 18,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 0,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  iconSize: 16,
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                    });
                                  },
                                  color: theme.hintColor,
                                )
                              : null,
                            isDense: true,
                            isCollapsed: false,
                            alignLabelWithHint: true,
                          ),
                          textAlignVertical: TextAlignVertical.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                    ),
                  ),
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
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildContactSupport(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  Icons.support_agent,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
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
                  'Still Need Help?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Our support team is available to help you with any issues.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
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
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ContactSupportPage(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: const Text(
                    'Contact Support',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
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

  Widget _buildIssueSection(ThemeData theme, String title, List<Widget> items) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
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
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...items,
      ],
    );
  }

  Widget _buildIssueItem(ThemeData theme, String title, String solution, IconData icon) {
    final isDark = theme.brightness == Brightness.dark;
    final isExpanded = _expandedItems[title] ?? false;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _expandedItems[title] = !isExpanded;
            });
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        // Icona con effetto vetro semi-trasparente
                        color: isDark 
                            ? Colors.white.withOpacity(0.2)
                            : Colors.white.withOpacity(0.3),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark 
                              ? Colors.white.withOpacity(0.3)
                              : Colors.white.withOpacity(0.5),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isDark 
                              ? Colors.black.withOpacity(0.3)
                              : Colors.black.withOpacity(0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                          BoxShadow(
                            color: isDark 
                              ? Colors.white.withOpacity(0.1)
                              : Colors.white.withOpacity(0.4),
                            blurRadius: 1,
                            spreadRadius: -1,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return LinearGradient(
                            colors: [
                              const Color(0xFF667eea),
                              const Color(0xFF764ba2),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            transform: GradientRotation(135 * 3.14159 / 180),
                          ).createShader(bounds);
                        },
                        child: Icon(
                          icon,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: isDark ? Colors.white : Colors.black87,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        solution,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                  crossFadeState: isExpanded 
                      ? CrossFadeState.showSecond 
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 300),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // New method for social platform issues that uses actual logos
  Widget _buildSocialIssueItem(ThemeData theme, String platform, String title, String solution) {
    final isDark = theme.brightness == Brightness.dark;
    final logoPath = _platformLogos[platform];
    final isExpanded = _expandedItems[title] ?? false;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _expandedItems[title] = !isExpanded;
            });
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        // Icona con effetto vetro semi-trasparente
                        color: isDark 
                            ? Colors.white.withOpacity(0.2)
                            : Colors.white.withOpacity(0.3),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark 
                              ? Colors.white.withOpacity(0.3)
                              : Colors.white.withOpacity(0.5),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isDark 
                              ? Colors.black.withOpacity(0.3)
                              : Colors.black.withOpacity(0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                          BoxShadow(
                            color: isDark 
                              ? Colors.white.withOpacity(0.1)
                              : Colors.white.withOpacity(0.4),
                            blurRadius: 1,
                            spreadRadius: -1,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: logoPath != null 
                        ? Image.asset(
                            logoPath,
                            width: 32,
                            height: 32,
                          )
                        : ShaderMask(
                            shaderCallback: (Rect bounds) {
                              return LinearGradient(
                                colors: [
                                  const Color(0xFF667eea),
                                  const Color(0xFF764ba2),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                transform: GradientRotation(135 * 3.14159 / 180),
                              ).createShader(bounds);
                            },
                            child: Icon(
                              Icons.device_unknown,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: isDark ? Colors.white : Colors.black87,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        solution,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                  crossFadeState: isExpanded 
                      ? CrossFadeState.showSecond 
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 300),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Updated method to use the new _buildSocialIssueItem for social media section
  List<Widget> _buildSectionItems(ThemeData theme, String sectionTitle, List<dynamic> items) {
    if (sectionTitle == 'Social Media Connection') {
      return items.map((item) {
        String platform = '';
        
        if (item['title'].contains('Instagram')) {
          platform = 'Instagram';
        } else if (item['title'].contains('Facebook')) {
          platform = 'Facebook';
        } else if (item['title'].contains('YouTube')) {
          platform = 'YouTube';
        } else if (item['title'].contains('TikTok')) {
          platform = 'TikTok';
        } else if (item['title'].contains('Twitter') || item['title'].contains('X')) {
          platform = 'Twitter';
        } else if (item['title'].contains('Threads')) {
          platform = 'Threads';
        }
        
        return _buildSocialIssueItem(
          theme,
          platform,
          item['title'],
          item['solution'],
        );
      }).toList();
    } else {
      return items.map((item) => _buildIssueItem(
        theme,
        item['title'],
        item['solution'],
        item['icon'],
      )).toList();
    }
  }

  // Topic dropdown widget
  Widget _buildTopicDropdown() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 7, vertical: 0),
      decoration: BoxDecoration(
        // Effetto vetro semi-trasparente opaco
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _showTopicDropdown = !_showTopicDropdown;
                    if (_showTopicDropdown) {
                      _topicAnimationController.forward();
                    } else {
                      _topicAnimationController.reverse();
                    }
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.category,
                              color: const Color(0xFF6C63FF),
                              size: 18,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            _selectedTopic,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.textTheme.titleLarge?.color,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      AnimatedIcon(
                        icon: AnimatedIcons.menu_close,
                        progress: _topicAnimation,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              SizeTransition(
                sizeFactor: _topicAnimation,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: theme.colorScheme.outline.withOpacity(0.08),
                        width: 1.2,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildTopicOption('All Topics'),
                      _buildTopicOption('General App Issues'),
                      _buildTopicOption('Authentication Issues'),
                      _buildTopicOption('Social Media Connection'),
                      _buildTopicOption('Video Upload & Publishing'),
                      _buildTopicOption('Account & Dashboard Management'),
                      _buildTopicOption('Notifications & Suggestions'),
                      _buildTopicOption('Performance & Optimization'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopicOption(String topic) {
    final theme = Theme.of(context);
    final isSelected = _selectedTopic == topic;
    final isDark = theme.brightness == Brightness.dark;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTopic = topic;
          _showTopicDropdown = false;
          _topicAnimationController.reverse();
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outline.withOpacity(0.05),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected 
                    ? const Color(0xFF6C63FF).withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                _getTopicIcon(topic),
                size: 16,
                color: isSelected 
                    ? const Color(0xFF6C63FF)
                    : theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                topic,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected 
                      ? theme.colorScheme.primary
                      : theme.textTheme.bodyMedium?.color,
                  fontSize: 14,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                size: 18,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  IconData _getTopicIcon(String topic) {
    switch (topic) {
      case 'All Topics':
        return Icons.all_inclusive;
      case 'General App Issues':
        return Icons.phone_android;
      case 'Authentication Issues':
        return Icons.security;
      case 'Social Media Connection':
        return Icons.share;
      case 'Video Upload & Publishing':
        return Icons.video_library;
      case 'Account & Dashboard Management':
        return Icons.dashboard;
      case 'Notifications & Suggestions':
        return Icons.notifications;
      case 'Performance & Optimization':
        return Icons.speed;
      default:
        return Icons.category;
    }
  }
} 