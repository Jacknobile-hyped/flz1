import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _version = packageInfo.version;
      _isLoading = false;
    });
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
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
          // Main content area - no padding, content can scroll behind floating header
          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 100, 24, 24), // Aggiunto padding superiore per la top bar
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary.withOpacity(0.2),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                                                     child: CircleAvatar(
                             radius: 60,
                             backgroundColor: isDark ? Colors.grey[800] : Color(0xFF667eea).withOpacity(0.1),
                             backgroundImage: const AssetImage('assets/onboarding/circleICON.png'),
                           ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
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
                                 'Fluzar',
                                 style: theme.textTheme.headlineMedium?.copyWith(
                                   fontWeight: FontWeight.bold,
                                   color: Colors.white,
                                   fontFamily: 'Ethnocentric',
                                 ),
                               ),
                             ),
                          ],
                        ),

                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            // Effetto vetro semi-trasparente opaco
                            color: isDark 
                                ? Colors.white.withOpacity(0.15) 
                                : Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(16),
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
                          child: Text(
                            'Your all-in-one AI platform for social media content management',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: isDark ? Colors.white : Colors.black87,
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        _buildInfoCard(
                          context,
                          'Developed by',
                          'Fluzar Team',
                          Icons.people,
                        ),
                        const SizedBox(height: 16),
                        _buildInfoCard(
                          context,
                          'Website',
                          'fluzar.com',
                          Icons.language,
                          onTap: () => _launchURL('https://fluzar.com/'),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoCard(
                          context,
                          'Email',
                          'fluzar.contact@gmail.com',
                          Icons.email,
                          onTap: () => _launchURL('mailto:fluzar.contact@gmail.com'),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          '© 2025 Fluzar. All rights reserved.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
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
                               child: TextButton(
                                 onPressed: () => _launchURL('https://fluzar.com/privacy-policy'),
                                 child: Text(
                                   'Privacy Policy',
                                   style: TextStyle(
                                     color: Colors.white,
                                   ),
                                 ),
                               ),
                             ),
                             const SizedBox(width: 20),
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
                               child: TextButton(
                                 onPressed: () => _launchURL('https://fluzar.com/terms-conditions'),
                                 child: Text(
                                   'Terms & Conditions',
                                   style: TextStyle(
                                     color: Colors.white,
                                   ),
                                 ),
                               ),
                             ),
                          ],
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

  Widget _buildInfoCard(
    BuildContext context,
    String title,
    String value,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            // Effetto vetro semi-trasparente opaco
            color: isDark 
                ? Colors.white.withOpacity(0.15) 
                : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(16),
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
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
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
                      blurRadius: 8,
                      offset: const Offset(0, 2),
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
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white.withOpacity(0.7) : Colors.black87.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
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
                    Icons.arrow_forward_ios,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
} 