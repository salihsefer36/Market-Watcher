import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> signInWithGoogle(BuildContext context) async {
    final localizations = AppLocalizations.of(context)!;
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
        _showErrorSnackBar(context, localizations.noDataFound); // Örnek bir hata metni
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
            // Hata kutusu için daha koyu kırmızı gradyan
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
      body: Container(
        // Arka plan için çekici, derin bir gradyan
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.grey.shade900, Colors.black], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 40.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                // Logo/İkon: Daha büyük, daha fazla gölgeli ve canlı
                Icon(
                  Icons.insights_rounded,
                  size: 100.sp, 
                  color: Colors.amber.shade400, 
                  shadows: [
                    BoxShadow(color: Colors.amber.shade400.withOpacity(0.8), blurRadius: 30.0, spreadRadius: 5.0)
                  ],
                ),
                SizedBox(height: 24.h),
                Text(
                  localizations.marketWatcher, 
                  textAlign: TextAlign.center, 
                  style: TextStyle(
                    fontSize: 44.sp, 
                    fontWeight: FontWeight.w900, // Daha kalın font
                    color: Colors.white, 
                    letterSpacing: 1.5,
                  )
                ),
                SizedBox(height: 12.h),
                Text(localizations.instantMarketAlarms, textAlign: TextAlign.center, style: TextStyle(fontSize: 18.sp, color: Colors.grey.shade300, fontWeight: FontWeight.w300)),
                const Spacer(flex: 3),
                // Google Butonu: Daha belirgin bir gölge ve efekt
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFFB300), Colors.amberAccent], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.shade400.withOpacity(0.4), 
                        blurRadius: 15, 
                        offset: const Offset(0, 8)
                      )
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16.r),
                      onTap: () => signInWithGoogle(context),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 18.h, horizontal: 24.w),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Basit bir Google ikonu yerine, gerçek logo görseli (varsayımsal)
                            // Image.asset('assets/images/google_logo.png', height: 24.h),
                            Image.network('https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/200px-Google_%22G%22_logo.svg.png', height: 24.h),
                            SizedBox(width: 12.w),
                            Text(localizations.continueWithGoogle, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.black)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(flex: 1),
                Text(
                  "localizations.loginPrivacyNote",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.sp, color: Colors.grey.shade600),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}