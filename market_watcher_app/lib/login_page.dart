import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:flutter_animate/flutter_animate.dart';

String _generateRandomString([int length = 32]) {
  final random = Random.secure();
  final values = List<int>.generate(length, (i) => random.nextInt(256));
  return base64Url.encode(values);
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _performSignIn(Future<void> Function() signInMethod) async {
    HapticFeedback.lightImpact();
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await signInMethod();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      if (kIsWeb) {
        GoogleAuthProvider authProvider = GoogleAuthProvider();
        await FirebaseAuth.instance.signInWithPopup(authProvider);
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) return;
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
    } catch (e) {
      print('Google Sign-In hatası: $e');
      if (context.mounted) {
        _showErrorSnackBar(context, "Error"); // Genel bir hata mesajı
      }
    }
  }

  Future<void> signInWithFacebook(BuildContext context) async {
    try {
      final result = await FacebookAuth.instance.login();
      if (result.status == LoginStatus.success) {
        final OAuthCredential credential = FacebookAuthProvider.credential(result.accessToken!.tokenString);
        await FirebaseAuth.instance.signInWithCredential(credential);
      } else {
        if (context.mounted) {
          _showErrorSnackBar(context, result.message ?? "Error");
        }
      }
    } catch (e) {
      print('Facebook Sign-In hatası: $e');
      if (context.mounted) {
        _showErrorSnackBar(context, "Error");
      }
    }
  }

  Future<void> signInWithApple(BuildContext context) async {
    final rawNonce = _generateRandomString();
    final nonce = sha256.convert(utf8.encode(rawNonce)).toString();

    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: nonce,
      );
      final credential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      print('Apple Sign-In hatası: $e');
      if (context.mounted) {
        _showErrorSnackBar(context, "Error");
      }
    }
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.red.shade800, Colors.redAccent.shade700]),
            borderRadius: BorderRadius.circular(16.r),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12.w),
              Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey.shade900, Colors.black],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),
                  
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Icon(
                      Icons.insights_rounded,
                      size: 100.sp,
                      color: Colors.amber.shade400,
                      shadows: [
                        BoxShadow(color: Colors.amber.shade400.withOpacity(0.8), blurRadius: 30.0, spreadRadius: 5.0)
                      ],
                    ),
                  ),
                  SizedBox(height: 24.h),
                  
                  Text(
                    localizations.marketWatcher,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 40.sp, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5)
                  ),
                  SizedBox(height: 12.h),
                  
                  Text(
                    localizations.instantMarketAlarms,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18.sp, color: Colors.grey.shade300, fontWeight: FontWeight.w300)
                  ),
                  const Spacer(flex: 3),

                  _buildLoginButton(
                    onTap: () => _performSignIn(() => signInWithGoogle(context)),
                    gradientColors: const [Color(0xFFFFB300), Colors.amberAccent],
                    icon: Image.asset('assets/images/google_logo.png', height: 24.h),
                    text: localizations.continueWithGoogle,
                    textColor: Colors.black,
                  ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.5, curve: Curves.easeOut),
                  
                  SizedBox(height: 16.h),
                  
                  _buildLoginButton(
                    onTap: () => _performSignIn(() => signInWithFacebook(context)),
                    gradientColors: const [Color(0xFF1877F2), Color(0xFF4267B2)],
                    icon: const Icon(Icons.facebook, color: Colors.white),
                    text: "Continue with Facebook",
                    textColor: Colors.white,
                  ).animate().fadeIn(delay: 600.ms, duration: 500.ms).slideY(begin: 0.5, curve: Curves.easeOut),
                  
                  SizedBox(height: 16.h),
                  
                  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS))
                    SignInWithAppleButton(
                      text: "Continue With Apple",
                      style: SignInWithAppleButtonStyle.white,
                      borderRadius: BorderRadius.all(Radius.circular(16.r)),
                      onPressed: () => _performSignIn(() => signInWithApple(context)),
                      height: 60.h,
                    ).animate().fadeIn(delay: 700.ms, duration: 500.ms).slideY(begin: 0.5, curve: Curves.easeOut),
                    
                  const Spacer(flex: 2), // KALDIRILDI: Misafir butonu ve altındaki spacer.
                ],
              ),
            ),
          ),

          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: CircularProgressIndicator(color: Colors.amber.shade400),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoginButton({
    required VoidCallback onTap,
    required List<Color> gradientColors,
    required Widget icon,
    required String text,
    required Color textColor,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
              color: gradientColors[0].withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 8)
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16.r),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18.h, horizontal: 24.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                SizedBox(width: 12.w),
                Text(text, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: textColor)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}