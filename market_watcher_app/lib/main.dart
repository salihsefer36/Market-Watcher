import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import 'settings_page.dart';
import 'package:provider/provider.dart'; 
import 'l10n/app_localizations.dart';
import 'locale_provider.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('Background message received: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(
    ChangeNotifierProvider(
      create: (context) => LocaleProvider(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) {
          return const MyApp();
        },
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
 
    return MaterialApp(
      // --- BU ÜÇ SATIR HATAYI ÇÖZECEKTİR ---
      locale: localeProvider.locale, // Mevcut aktif dili ayarlar
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // -------------------------------------

      onGenerateTitle: (context) => AppLocalizations.of(context)!.marketWatcher,

      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.amber.shade600,
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.amber,
          accentColor: Colors.orangeAccent,
          backgroundColor: Colors.grey.shade900,
        ),
        cardTheme: CardThemeData(
          color: Colors.grey.shade900,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.r),
          ),
          shadowColor: Colors.black.withOpacity(0.6),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade800,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: Colors.amber.shade700),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: Colors.amber.shade500),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: Colors.amber.shade400, width: 2.w),
          ),
          hintStyle: const TextStyle(color: Colors.grey),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber.shade700,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
            textStyle: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
            ),
            shadowColor: Colors.black.withOpacity(0.6),
            elevation: 6,
          ),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white),
          bodyLarge: TextStyle(color: Colors.white),
          titleLarge: TextStyle(
            color: Colors.amber,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Colors.amber)),
          );
        }
        return HomePage();
      },
    );
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  // LoginPage içinde
  Future<void> signInWithGoogle(BuildContext context) async {
     final localizations = AppLocalizations.of(context)!;
    try {
      if (kIsWeb) {
        GoogleAuthProvider authProvider = GoogleAuthProvider();
        await FirebaseAuth.instance.signInWithPopup(authProvider);
      } else {
        final googleUser = await GoogleSignIn().signIn();
        // 1. Kullanıcı iptal ederse, fonksiyon sessizce sonlanır.
        if (googleUser == null) return; 

        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        // 2. Başarılı olursa, AuthGate yönlendirmeyi yapar.
        // Hata olursa, doğrudan catch bloğuna atlar.
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
    } catch (e) {
      print('Google Sign-In hatası: $e');
      // 3. Her türlü hata burada yakalanır ve kullanıcıya gösterilir.
      if (context.mounted) {
        _showErrorSnackBar(context, localizations.couldNotGetNotificationToken);
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
            gradient: LinearGradient(
              colors: [Colors.red.shade700, Colors.redAccent.shade400],
            ),
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
        // 1. Arka Plana Derinlik Katıyoruz
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.grey.shade900, Colors.black],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 40.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // 2. Uygulama Logosu ve Başlığı
                Icon(
                  Icons.insights_rounded, // Tematik bir ikon
                  size: 80.sp,
                  color: Colors.amber.shade400,
                  shadows: [
                    BoxShadow(
                      color: Colors.amber.shade400.withOpacity(0.5),
                      blurRadius: 18.0,
                      spreadRadius: 2.0,
                    )
                  ],
                ),
                SizedBox(height: 16.h),
                Text(localizations.marketWatcher, textAlign: TextAlign.center, style: TextStyle(fontSize: 40.sp, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(height: 8.h),
                Text(localizations.instantMarketAlarms, textAlign: TextAlign.center, style: TextStyle(fontSize: 16.sp, color: Colors.grey.shade400)),

                const Spacer(flex: 3),

                // 3. Giriş Butonu
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.amber, Colors.orangeAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16.r), // Daha modern bir border radius
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16.r),
                      onTap: () => signInWithGoogle(context),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 24.w),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/images/google_logo.png',
                              height: 24.h,
                            ),
                            SizedBox(width: 12.w),
                            Text(localizations.continueWithGoogle, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.black)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final String backendBaseUrl = "http://127.0.01:8000";
  List<Map<String, dynamic>> _followedItems = [];
  bool _loading = false;

  // Backend: kullanıcının alarmlarını çek
  Future<void> _fetchUserAlarms() async {
    setState(() => _loading = true);
    try {
      // 1. Değişken adını anlamlı hale getirdik.
      final userUid = _auth.currentUser?.uid;
      
      // UID yoksa (kullanıcı giriş yapmamışsa) işlemi durdur.
      if (userUid == null) {
        setState(() {
          _followedItems = []; // Listeyi boşalt
          _loading = false;
        });
        return;
      }

      // 2. Sorgu parametresini "user_uid" olarak düzelttik.
      final uri = Uri.parse("$backendBaseUrl/alerts?user_uid=$userUid"); 
      final res = await http.get(uri);

      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        if (mounted) { // Asenkron işlem sonrası widget'ın hala ağaçta olduğundan emin ol
          setState(() {
            _followedItems = data.map((e) {
              final Map<String, dynamic> item = Map<String, dynamic>.from(e);
              if (item['market'] == 'CRYPTO' && item['symbol'].endsWith('T')) {
                item['symbol'] = item['symbol'].substring(0, item['symbol'].length - 1);
              }
              return item;
            }).toList();
          });
        }
      }
    } catch (e) {
      print("Error fetching alerts: $e");
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _createOrEditAlarm(String market,String symbol,double percentage, {int? editId,}) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      // 1. Firebase Auth'dan UID'yi al
      final userUid = _auth.currentUser?.uid;
      if (userUid == null) {
        // Kullanıcı giriş yapmamışsa işlem yapma
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.pleaseSignInFirst)));
        return;
      }

      // 2. Firebase Messaging'den FCM Cihaz Token'ını al
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.couldNotGetNotificationToken)));
        return;
      }

      final exists = _followedItems.any((alarm) {
        if (editId != null && alarm['id'] == editId) return false;

        String alarmSymbol = alarm['symbol'];
        String checkSymbol = symbol;

        if (alarm['market'] == 'CRYPTO') {
          if (alarmSymbol.endsWith("T")) alarmSymbol = alarmSymbol.substring(0, alarmSymbol.length - 1);
          if (alarmSymbol.endsWith("USDT")) alarmSymbol = alarmSymbol.substring(0, alarmSymbol.length - 4);

          if (checkSymbol.endsWith("T")) checkSymbol = checkSymbol.substring(0, checkSymbol.length - 1);
          if (checkSymbol.endsWith("USDT")) checkSymbol = checkSymbol.substring(0, checkSymbol.length - 4);
        }

        if (alarm['market'] == 'METALS') {
          alarmSymbol = alarmSymbol.toUpperCase();
          checkSymbol = checkSymbol.toUpperCase();
        }

        return alarm['market'] == market && alarmSymbol == checkSymbol;
      });

      if (exists) {
        String displaySymbol = symbol;

        if (market == 'CRYPTO' && displaySymbol.endsWith('USDT')) {
          displaySymbol = displaySymbol.substring(0, displaySymbol.length - 1); 
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating, 
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            backgroundColor: Colors.transparent, 
            elevation: 0,
            content: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.redAccent.shade200, Colors.red.shade900],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 8,
                    offset: const Offset(2, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      localizations.alarmAlreadyExists(displaySymbol, market),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return;
      }

      final uri = editId != null
          ? Uri.parse("$backendBaseUrl/alerts/$editId") // edit
          : Uri.parse("$backendBaseUrl/alerts");       // create

      final body = jsonEncode({
        "market": market,
        "symbol": symbol,
        "percentage": percentage,
        "user_uid": userUid,       // <-- EKLENDİ
        "user_token": fcmToken     // <-- Artık bu cihaz token'ı
      });

      final res = editId != null
          ? await http.put(uri, headers: {"Content-Type": "application/json"}, body: body)
          : await http.post(uri, headers: {"Content-Type": "application/json"}, body: body);

      if (res.statusCode == 200) {
        await _fetchUserAlarms(); // UI güncelle
      } else {
        print("Error creating/editing alarm: ${res.body}");
      }
    } catch (e) {
      print("Create/Edit alarm error: $e");
    }
  }

  // Backend: alarm sil
  Future<void> _deleteAlarm(int id) async {
    try {
      final uri = Uri.parse("$backendBaseUrl/alerts/$id");
      final res = await http.delete(uri);
      if (res.statusCode == 200) {
        await _fetchUserAlarms(); // UI güncelle
      } else {
        print("Error deleting alarm: ${res.body}");
      }
    } catch (e) {
      print("Delete alarm error: $e");
    }
  }

  void _openSetAlarmDialog(BuildContext context, AppLocalizations localizations) {
    String? selectedMarket;
    String? selectedSymbol;
    double? selectedPercentage;

    final markets = ['BIST', 'NASDAQ', 'CRYPTO', 'METALS'];
    final percentages = [1, 2, 5, 10];
    List<String> symbolsForMarket = [];

    bool _isLoadingSymbols = false;
    final localizations = AppLocalizations.of(context)!;

    Future<List<String>> _fetchSymbolsForMarket(String market) async {
      try {
        final uri = Uri.parse("$backendBaseUrl/symbols_with_name?market=$market");
        final res = await http.get(uri);
        if (res.statusCode == 200) {
          final List<dynamic> data = jsonDecode(res.body);
          return data.map((e) => e['symbol'].toString()).toList();
        }
      } catch (e) {
        print("Error fetching symbols for $market: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.marketSymbolsCouldNotBeLoaded(market))));
        }
      }
      return [];
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(24.w), 
          child: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView( 
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.grey.shade900, Colors.black87],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(color: Colors.amber.withOpacity(0.5)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        localizations.setAlarm,
                        style: TextStyle(
                          color: Colors.amber.shade400,
                          fontSize: 24.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 24.h),
                      
                      _buildDropdownContainer(
                        icon: Icons.store_mall_directory_outlined,
                        child: DropdownButton<String>(
                          dropdownColor: Colors.grey.shade800,
                          isExpanded: true,
                          underline: const SizedBox(),
                          value: selectedMarket,
                          hint: Text(localizations.selectMarket, style: TextStyle(color: Colors.grey)),
                          items: markets.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(color: Colors.white)))).toList(),
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() {
                              _isLoadingSymbols = true;
                              selectedMarket = value;
                              selectedSymbol = null;
                              symbolsForMarket = [];
                            });
                            
                            final symbols = await _fetchSymbolsForMarket(value);
                            
                            setState(() {
                              symbolsForMarket = symbols;
                              _isLoadingSymbols = false;
                            });
                          },
                        ),
                      ),
                      SizedBox(height: 16.h),
                      
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 50.h, 
                        child: _isLoadingSymbols
                            ? Center(child: CircularProgressIndicator(color: Colors.amber.shade600, strokeWidth: 2.5))
                            : (selectedMarket != null
                                ? _buildDropdownContainer(
                                    icon: Icons.analytics_outlined,
                                    child: DropdownButton<String>(
                                      dropdownColor: Colors.grey.shade800,
                                      isExpanded: true,
                                      underline: const SizedBox(),
                                      hint: Text(localizations.selectSymbol, style: TextStyle(color: Colors.grey)),
                                      value: symbolsForMarket.contains(selectedSymbol) ? selectedSymbol : null,
                                      items: symbolsForMarket.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: Colors.white)))).toList(),
                                      onChanged: (value) => setState(() => selectedSymbol = value),
                                    ),
                                  )
                                : const SizedBox()), // Market seçilmediyse boş
                      ),
                      SizedBox(height: 16.h),
                      
                      // --- Percentage Dropdown ---
                      _buildDropdownContainer(
                        icon: Icons.percent_rounded,
                        child: DropdownButton<double>(
                          dropdownColor: Colors.grey.shade800,
                          isExpanded: true,
                          underline: const SizedBox(),
                          hint: Text(localizations.selectChangePercent, style: TextStyle(color: Colors.grey)),
                          value: selectedPercentage,
                          items: percentages.map((p) => DropdownMenuItem(value: p.toDouble(), child: Text('$p%', style: const TextStyle(color: Colors.white)))).toList(),
                          onChanged: (value) => setState(() => selectedPercentage = value),
                        ),
                      ),
                      SizedBox(height: 24.h),
                      
                      // --- Butonlar ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(localizations.cancel, style: TextStyle(color: Colors.grey)),
                          ),
                          SizedBox(width: 12.w),
                          ElevatedButton(
                            onPressed: (selectedMarket != null && selectedSymbol != null && selectedPercentage != null)
                                ? () async {
                                    String formattedSymbol = selectedSymbol!;
                                    if (selectedMarket == 'CRYPTO') {
                                      // Önemli Düzeltme: Backend'e 'USDT' olarak göndermeliyiz
                                      formattedSymbol = "${selectedSymbol!.toUpperCase()}USDT";
                                    }
                                    await _createOrEditAlarm(
                                      selectedMarket!,
                                      formattedSymbol,
                                      selectedPercentage!,
                                    );
                                    Navigator.pop(context);
                                  }
                                : null, // Buton, tüm seçimler yapılana kadar pasif kalır
                            child: Text(localizations.setAlarm),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDropdownContainer({required IconData icon, required Widget child}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber.shade600, size: 20.sp),
          SizedBox(width: 12.w),
          Expanded(child: child),
        ],
      ),
    );
  }

  void _openEditAlarmDialog(BuildContext context, Map<String, dynamic> alert, AppLocalizations localizations) {
    String? selectedMarket = alert['market'];
    String? selectedSymbol = alert['symbol'];
    if (selectedMarket == 'CRYPTO' && selectedSymbol != null && selectedSymbol.endsWith('USDT')) {
      selectedSymbol = selectedSymbol.substring(0, selectedSymbol.length - 4);
    }
    
    double? selectedPercentage = alert['percentage']?.toDouble();

    final markets = ['BIST', 'NASDAQ', 'CRYPTO', 'METALS'];
    final percentages = [1, 2, 5, 10];
    List<String> symbolsForMarket = [];
    bool _isLoadingSymbols = false;

    Future<List<String>> _fetchSymbolsForMarket(String market) async {
      try {
        final uri = Uri.parse("$backendBaseUrl/symbols_with_name?market=$market");
        final res = await http.get(uri);
        if (res.statusCode == 200) {
          final List<dynamic> data = jsonDecode(res.body);
          return data.map((e) => e['symbol'].toString()).toList();
        }
      } catch (e) {
        print("Error fetching symbols for $market: $e");
      }
      return [];
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(24.w),
          child: StatefulBuilder(
            builder: (context, setState) {

              if (selectedMarket != null && symbolsForMarket.isEmpty && !_isLoadingSymbols) {
                setState(() => _isLoadingSymbols = true);
                _fetchSymbolsForMarket(selectedMarket!).then((symbols) {
                  setState(() {
                    symbolsForMarket = symbols;
                    _isLoadingSymbols = false;
                  });
                });
              }

              return SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.grey.shade900, Colors.black87],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(color: Colors.amber.withOpacity(0.5)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        localizations.editAlarm,
                        style: TextStyle(
                          color: Colors.amber.shade400,
                          fontSize: 24.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 24.h),
                      
                      _buildDropdownContainer(
                        icon: Icons.store_mall_directory_outlined,
                        child: DropdownButton<String>(
                          dropdownColor: Colors.grey.shade800,
                          isExpanded: true,
                          underline: const SizedBox(),
                          value: selectedMarket,
                          items: markets.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(color: Colors.white)))).toList(),
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() {
                              _isLoadingSymbols = true;
                              selectedMarket = value;
                              selectedSymbol = null;
                              symbolsForMarket = [];
                            });
                            final symbols = await _fetchSymbolsForMarket(value);
                            setState(() {
                              symbolsForMarket = symbols;
                              _isLoadingSymbols = false;
                            });
                          },
                        ),
                      ),
                      SizedBox(height: 16.h),
                      
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 50.h,
                        child: _isLoadingSymbols
                            ? Center(child: CircularProgressIndicator(color: Colors.amber.shade600, strokeWidth: 2.5))
                            : _buildDropdownContainer(
                                icon: Icons.analytics_outlined,
                                child: DropdownButton<String>(
                                  dropdownColor: Colors.grey.shade800,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  value: symbolsForMarket.contains(selectedSymbol) ? selectedSymbol : null,
                                  hint: Text(localizations.selectSymbol, style: TextStyle(color: Colors.grey)),
                                  items: symbolsForMarket.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: Colors.white)))).toList(),
                                  onChanged: (value) => setState(() => selectedSymbol = value),
                                ),
                              ),
                      ),
                      SizedBox(height: 16.h),
                      
                      _buildDropdownContainer(
                        icon: Icons.percent_rounded,
                        child: DropdownButton<double>(
                          dropdownColor: Colors.grey.shade800,
                          isExpanded: true,
                          underline: const SizedBox(),
                          value: selectedPercentage,
                          hint: Text(localizations.selectChangePercent, style: TextStyle(color: Colors.grey)),
                          items: percentages.map((p) => DropdownMenuItem(value: p.toDouble(), child: Text('$p%', style: const TextStyle(color: Colors.white)))).toList(),
                          onChanged: (value) => setState(() => selectedPercentage = value),
                        ),
                      ),
                      SizedBox(height: 24.h),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(localizations.cancel, style: TextStyle(color: Colors.grey)),
                          ),
                          SizedBox(width: 12.w),
                          ElevatedButton(
                            onPressed: () async {
                              if (selectedMarket != null && selectedSymbol != null && selectedPercentage != null) {
                                String formattedSymbol = selectedSymbol!;
                                if (selectedMarket == 'CRYPTO') {
                                  formattedSymbol = "${selectedSymbol!.toUpperCase()}USDT";
                                }
                                await _createOrEditAlarm(
                                  selectedMarket!,
                                  formattedSymbol,
                                  selectedPercentage!,
                                  editId: alert['id'],
                                );
                                Navigator.pop(context);
                              }
                            },
                            child: Text(localizations.save),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchUserAlarms();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black,
        title: Text(
          user?.displayName ?? localizations.marketWatcher,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22.sp,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: Colors.amber, size: 30.sp,),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
        child: Column(
          children: [
            Container(
              height: MediaQuery.of(context).size.height * 0.55,
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.grey.shade900.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    localizations.followedAlarms,
                    style: TextStyle(
                      color: Colors.amber.shade400,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(color: Colors.grey, height: 24),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator(color: Colors.amber))
                        : _followedItems.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.notifications_off_outlined, color: Colors.grey, size: 48.sp),
                                    SizedBox(height: 16.h),
                                    Text(
                                      localizations.noAlarmsYet,
                                      style: TextStyle(color: Colors.grey, fontSize: 16.sp),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _fetchUserAlarms,
                                color: Colors.amber,
                                backgroundColor: Colors.grey.shade900,
                                child: ListView.builder(
                                  itemCount: _followedItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _followedItems[index];
                                    String symbol = item['symbol'] ?? '';
                                    if (item['market'] == 'CRYPTO' && symbol.endsWith('USDT')) {
                                      symbol = symbol.substring(0, symbol.length - 4);
                                    }
                                    return Slidable(
                                      key: ValueKey(item['id']),
                                      endActionPane: ActionPane(
                                        motion: const DrawerMotion(),
                                        extentRatio: 0.25,
                                        children: [
                                          SlidableAction(
                                            onPressed: (context) {
                                              _followedItems.removeAt(index);
                                              setState(() {});
                                              _deleteAlarm(item['id']);
                                            },
                                            backgroundColor: Colors.red.shade700,
                                            foregroundColor: Colors.white,
                                            icon: Icons.delete_forever,
                                            label: localizations.delete,
                                            borderRadius: BorderRadius.circular(12.r),
                                          ),
                                        ],
                                      ),
                                      child: ListTile(
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.amber.withOpacity(0.1),
                                          child: Icon(Icons.notifications_active_outlined, color: Colors.amber.shade400),
                                        ),
                                        title: Text(symbol, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.sp)),
                                        subtitle: Text(item['market'] ?? '', style: TextStyle(color: Colors.grey.shade400, fontSize: 12.sp)),
                                        trailing: Text('%${item['percentage']}', style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w500)),
                                        onTap: () => _openEditAlarmDialog(context, item, localizations),
                                      ),
                                    );
                                  },
                                ),
                              ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 36.h),

            SizedBox(
              width: double.infinity,
              height: 55.h,
              child: ElevatedButton.icon(
                icon: Icon(Icons.add_alert_rounded ,size: 28.sp,),
                label: Text(
                  localizations.setAlarm,
                  style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                ),
                onPressed: () => _openSetAlarmDialog(context, localizations),
              ),
            ),
            SizedBox(height: 18.h),
            SizedBox(
              width: double.infinity,
              // 3. BUTON BOYUTU ARTIRILDI: Yükseklik 55.h olarak ayarlandı.
              height: 55.h,
              child: ElevatedButton.icon(
                icon: Icon(Icons.bar_chart_rounded, size: 28.sp,),
                label: Text(
                  localizations.watchMarket,
                  style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade800,
                  foregroundColor: Colors.amber,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => WatchMarketPage()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class WatchMarketPage extends StatefulWidget {
  const WatchMarketPage({super.key});

  @override
  State<WatchMarketPage> createState() => _WatchMarketPageState();
}

class _WatchMarketPageState extends State<WatchMarketPage> with SingleTickerProviderStateMixin {
  final String backendBaseUrl = "http://127.0.0.1:8000";
  
  Map<String, List<Map<String, dynamic>>> marketData = {
    "BIST": [],
    "NASDAQ": [],
    "CRYPTO": [],
    "METALS": [],
  };
  bool loading = true;

  // 2. TabController is defined for managing tabs.
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // The controller is initialized with a length matching the number of markets.
    _tabController = TabController(length: marketData.keys.length, vsync: this);
    fetchAllDataEfficiently(); // Switched to a more efficient data fetching method
  }

  @override
  void dispose() {
    _tabController.dispose(); // Clean up the controller when the page is closed
    super.dispose();
  }
  
  // --- A MORE EFFICIENT DATA FETCHING METHOD ---
  Future<void> fetchAllDataEfficiently() async {
    final localizations = AppLocalizations.of(context)!;
    if (!mounted) return;
    setState(() => loading = true);
    
    // Clear previous data
    marketData.forEach((key, value) => value.clear());

    try {
      // Fetch all prices and symbols in a single API call
      final res = await http.get(Uri.parse("$backendBaseUrl/prices"));
      if (res.statusCode == 200) {
        final List<dynamic> allData = jsonDecode(res.body);
        
        // Sort the data from the single endpoint into the correct market lists
        for (var item in allData) {
          final market = item['market'];
          if (market != null && marketData.containsKey(market)) {
            marketData[market]?.add(item);
          }
        }
      } else {
        throw Exception('Failed to load market data');
      }
    } catch (e) {
      print("Error fetching market data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.noDataFound),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.amber),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          localizations.watchMarketChart,
          style: TextStyle(
            color: Colors.amber,
            fontWeight: FontWeight.bold,
            fontSize: 22.sp,
          ),
        ),
        backgroundColor: Colors.black,
        // 3. A TabBar is added to the bottom of the AppBar.
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.grey,
          labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp),
          tabs: marketData.keys.map((market) => Tab(text: market)).toList(),
        ),
      ),
      backgroundColor: Colors.black,
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          // 4. The body is now a TabBarView, which displays content based on the selected tab.
          : TabBarView(
              controller: _tabController,
              children: marketData.keys.map((market) {
                final data = marketData[market] ?? [];
                final filteredData = data.where((item) => item['price'] != null && item['price'] > 0).toList();
                
                return _buildMarketList(market, filteredData);
              }).toList(),
            ),
    );
  }

  // 5. This new helper method builds the content for each tab.
  Widget _buildMarketList(String market, List<Map<String, dynamic>> data) {
    final localizations = AppLocalizations.of(context)!;
    return Column(
      children: [
        // Column Headers
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text(localizations.symbol, style: TextStyle(color: Colors.grey, fontSize: 12.sp))),
              Expanded(flex: 5, child: Text(localizations.name, style: TextStyle(color: Colors.grey, fontSize: 12.sp))),
              Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: Text(localizations.price, style: TextStyle(color: Colors.grey, fontSize: 12.sp)))),
            ],
          ),
        ),
        const Divider(color: Color(0xFF222222), height: 1),
        
        // The List
        Expanded(
          child: data.isEmpty
              ? Center(child: Text(localizations.noData, style: TextStyle(color: Colors.grey, fontSize: 16.sp)))
              : RefreshIndicator(
                  onRefresh: fetchAllDataEfficiently,
                  color: Colors.amber,
                  backgroundColor: Colors.grey.shade900,
                  child: ListView.separated(
                    itemCount: data.length,
                    separatorBuilder: (context, index) => const Divider(color: Color(0xFF222222), height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      final item = data[index];
                      final priceValue = item['price'] as num;
                      
                      String currencySymbol = (market == "BIST" || market == "METALS") ? "₺" : "\$";
                      String displayPrice = "${priceValue.toStringAsFixed(2)}$currencySymbol";
                      String displayName = item['name'] ?? item['symbol'] ?? '';
                      if (market == "METALS") displayName = "Gram $displayName";

                      // Clean crypto symbols for display
                      String displaySymbol = item['symbol'] ?? '';
                      if (market == "CRYPTO" && displaySymbol.endsWith('USDT')) {
                        displaySymbol = displaySymbol.substring(0, displaySymbol.length - 4);
                      }

                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(displaySymbol, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp)),
                            ),
                            Expanded(
                              flex: 5,
                              child: Text(displayName, style: TextStyle(color: Colors.grey.shade400, fontSize: 13.sp), overflow: TextOverflow.ellipsis),
                            ),
                            Expanded(
                              flex: 3,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(displayPrice, style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14.sp, letterSpacing: 0.5)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}