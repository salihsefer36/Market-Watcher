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

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('Background message received: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Market Watcher',
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
            borderRadius: BorderRadius.circular(20),
          ),
          shadowColor: Colors.black.withOpacity(0.6),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade800,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.amber.shade700),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.amber.shade500),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.amber.shade400, width: 2),
          ),
          hintStyle: const TextStyle(color: Colors.grey),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber.shade700,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
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
  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        GoogleAuthProvider authProvider = GoogleAuthProvider();
        return await FirebaseAuth.instance.signInWithPopup(authProvider);
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) return null;
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        return await FirebaseAuth.instance.signInWithCredential(credential);
      }
    } catch (e) {
      print('Google Sign-In hatası: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          padding: const EdgeInsets.all(24),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.5,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.grey.shade900, Colors.grey.shade800],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.amberAccent.shade700, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.7),
                blurRadius: 12,
                offset: const Offset(4, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Market Watcher',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade400,
                  shadows: [
                    Shadow(
                      color: Colors.black87,
                      offset: const Offset(2, 2),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.amber, Colors.orangeAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 6,
                      offset: const Offset(2, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final userCredential = await signInWithGoogle();
                      if (userCredential != null) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => HomePage()),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating, // ekranın altında yüzen tarz
                            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            backgroundColor: Colors.transparent, // şeffaf yapıp Container ile süsleyeceğiz
                            elevation: 0,
                            duration: const Duration(seconds: 3),
                            content: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.red.shade700, Colors.redAccent.shade400],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.6),
                                    blurRadius: 8,
                                    offset: const Offset(2, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.error_outline, color: Colors.white),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Giriş başarısız',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset('assets/images/google_logo.png', height: 24, width: 24),
                          const SizedBox(width: 12),
                          const Text(
                            'Google ile Giriş Yap',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
  final String backendBaseUrl = "http://192.168.0.104:8000";
  List<Map<String, dynamic>> _followedItems = [];
  bool _loading = false;
  Map<int, bool> _isDeleted = {};

  // Backend: kullanıcının alarmlarını çek
  Future<void> _fetchUserAlarms() async {
    setState(() => _loading = true);
    try {
      final userToken = _auth.currentUser?.uid ?? "test-user"; // fallback test user
      final uri = Uri.parse("$backendBaseUrl/alerts?user_token=$userToken");
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        setState(() {
          _followedItems = data.map((e) {
            final Map<String, dynamic> item = Map<String, dynamic>.from(e);

            // Eğer CRYPTO market ise ve sembol 'T' ile bitiyorsa sondaki 'T'yi at
            if (item['market'] == 'CRYPTO' && item['symbol'].endsWith('T')) {
              item['symbol'] = item['symbol'].substring(0, item['symbol'].length - 1);
            }

            return item;
          }).toList();
        });
      }
    } catch (e) {
      print("Error fetching alerts: $e");
    }
    setState(() => _loading = false);
  }

  Future<void> _createOrEditAlarm(String market,String symbol,double percentage, {int? editId,}) async {
    try {
      final userToken = _auth.currentUser?.uid ?? "test-user";

      String backendSymbol = symbol;
      if (market == 'METALS') {
        backendSymbol = symbol.toUpperCase();
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
                borderRadius: BorderRadius.circular(12),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Alarm already exists for $displaySymbol in $market',
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
        "symbol": backendSymbol,
        "percentage": percentage,
        "user_token": userToken
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

  void _openSetAlarmDialog(BuildContext context) {
    String? selectedMarket;
    String? selectedSymbol;
    double? selectedPercentage;

    final markets = ['BIST', 'NASDAQ', 'CRYPTO', 'METALS'];
    final percentages = [1, 2, 5, 10];
    List<String> symbolsForMarket = [];

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
          child: Container(
            width: MediaQuery.of(context).size.width * 0.2, // ekran genişliğinin %20'si
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey.shade900, Colors.grey.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amberAccent.shade700, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.7),
                  blurRadius: 10,
                  offset: const Offset(3, 4),
                ),
              ],
            ),
            child: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Set Alarm',
                      style: TextStyle(
                        color: Colors.amber.shade400,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black87,
                            offset: const Offset(1.5, 1.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Market Dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amberAccent, width: 1),
                      ),
                      child: DropdownButton<String>(
                        dropdownColor: Colors.grey.shade800,
                        isExpanded: true,
                        underline: const SizedBox(),
                        value: selectedMarket,
                        hint: const Text('Select Market', style: TextStyle(color: Colors.white)),
                        items: markets
                            .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m, style: const TextStyle(color: Colors.white)),
                                ))
                            .toList(),
                        onChanged: (value) async {
                          setState(() {
                            selectedMarket = value;
                            selectedSymbol = null;
                            symbolsForMarket = [];
                          });
                          if (value != null) {
                            final symbols = await _fetchSymbolsForMarket(value);
                            setState(() {
                              symbolsForMarket = symbols;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Symbol Dropdown
                    if (selectedMarket != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amberAccent, width: 1),
                        ),
                        child: DropdownButton<String>(
                          dropdownColor: Colors.grey.shade800,
                          isExpanded: true,
                          underline: const SizedBox(),
                          hint: const Text('Select Symbol', style: TextStyle(color: Colors.white)),
                          value: symbolsForMarket.contains(selectedSymbol) ? selectedSymbol : null,
                          items: symbolsForMarket
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s, style: const TextStyle(color: Colors.white)),
                                  ))
                              .toList(),
                          onChanged: (value) => setState(() => selectedSymbol = value),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Percentage Dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amberAccent, width: 1),
                      ),
                      child: DropdownButton<double>(
                        dropdownColor: Colors.grey.shade800,
                        isExpanded: true,
                        underline: const SizedBox(),
                        hint: const Text('Select Change %', style: TextStyle(color: Colors.white)),
                        value: selectedPercentage,
                        items: percentages
                            .map((p) => DropdownMenuItem(
                                  value: p.toDouble(),
                                  child: Text('$p%', style: const TextStyle(color: Colors.white)),
                                ))
                            .toList(),
                        onChanged: (value) => setState(() => selectedPercentage = value),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                          ),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () async {
                            if (selectedMarket != null &&
                                selectedSymbol != null &&
                                selectedPercentage != null) {
                              String formattedSymbol = selectedSymbol!;
                              if (selectedMarket == 'CRYPTO') {
                                formattedSymbol = "${selectedSymbol!.toUpperCase()}T";
                              }
                              await _createOrEditAlarm(
                                selectedMarket!,
                                formattedSymbol,
                                selectedPercentage!,
                              );
                              Navigator.pop(context);
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.amberAccent,
                            shadowColor: Colors.amberAccent.withOpacity(0.6),
                          ),
                          child: const Text('Set'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _openEditAlarmDialog(BuildContext context, Map<String, dynamic> alert) {
    String? selectedMarket = alert['market'] ?? 'BIST';
    String? selectedSymbol = alert['symbol'];
    double? selectedPercentage = alert['percentage']?.toDouble();

    final markets = ['BIST', 'NASDAQ', 'CRYPTO', 'METALS'];
    List<String> symbolsForMarket = [];

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
          child: Container(
            width: MediaQuery.of(context).size.width * 0.2, // ekran genişliğinin %40'ı
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey.shade900, Colors.grey.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amberAccent.shade700, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.7),
                  blurRadius: 10,
                  offset: const Offset(3, 4),
                ),
              ],
            ),
            child: StatefulBuilder(
              builder: (context, setState) {
                if (selectedMarket != null && symbolsForMarket.isEmpty) {
                  _fetchSymbolsForMarket(selectedMarket!).then((symbols) {
                    setState(() {
                      symbolsForMarket = symbols;
                    });
                  });
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Edit Alarm',
                      style: TextStyle(
                        color: Colors.amber.shade400,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black87,
                            offset: const Offset(1.5, 1.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Market Dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amberAccent, width: 1),
                      ),
                      child: DropdownButton<String>(
                        dropdownColor: Colors.grey.shade800,
                        isExpanded: true,
                        underline: const SizedBox(),
                        value: selectedMarket,
                        hint: const Text('Select Market', style: TextStyle(color: Colors.white)),
                        items: markets
                            .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m, style: const TextStyle(color: Colors.white)),
                                ))
                            .toList(),
                        onChanged: (value) async {
                          setState(() {
                            selectedMarket = value;
                            selectedSymbol = null;
                            symbolsForMarket = [];
                          });
                          if (value != null) {
                            final symbols = await _fetchSymbolsForMarket(value);
                            setState(() {
                              symbolsForMarket = symbols;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Symbol Dropdown
                    if (selectedMarket != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amberAccent, width: 1),
                        ),
                        child: DropdownButton<String>(
                          dropdownColor: Colors.grey.shade800,
                          isExpanded: true,
                          underline: const SizedBox(),
                          hint: const Text('Select Symbol', style: TextStyle(color: Colors.white)),
                          value: symbolsForMarket.contains(selectedSymbol) ? selectedSymbol : null,
                          items: symbolsForMarket
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s, style: const TextStyle(color: Colors.white)),
                                  ))
                              .toList(),
                          onChanged: (value) => setState(() => selectedSymbol = value),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Percentage Dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amberAccent, width: 1),
                      ),
                      child: DropdownButton<double>(
                        dropdownColor: Colors.grey.shade800,
                        isExpanded: true,
                        underline: const SizedBox(),
                        hint: const Text('Select Change %', style: TextStyle(color: Colors.white)),
                        value: selectedPercentage,
                        items: [1, 2, 5, 10]
                            .map((p) => DropdownMenuItem(
                                  value: p.toDouble(),
                                  child: Text('$p%', style: const TextStyle(color: Colors.white)),
                                ))
                            .toList(),
                        onChanged: (value) => setState(() => selectedPercentage = value),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                          ),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () async {
                            if (selectedMarket != null &&
                                selectedSymbol != null &&
                                selectedPercentage != null) {
                              await _createOrEditAlarm(
                                selectedMarket!,
                                selectedSymbol!,
                                selectedPercentage!,
                                editId: alert['id'],
                              );
                              Navigator.pop(context);
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.amberAccent,
                            shadowColor: Colors.amberAccent.withOpacity(0.6),
                          ),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          '📊 Market Watcher - ${user?.displayName ?? user?.email ?? ''}',
          style: const TextStyle(
            color: Color(0xFFFFD700),
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 1.2,
            shadows: [
              Shadow(
                offset: Offset(1.5, 1.5),
                blurRadius: 4,
                color: Colors.black87,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.language, color: Color(0xFFFFD700)),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFFFD700)),
            onPressed: () async {
              await _auth.signOut();
              await GoogleSignIn().signOut();
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => AuthGate()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sol taraf
           Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: MediaQuery.of(context).size.width * 0.15, // ekranın %15'i
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.amber, Colors.orangeAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openSetAlarmDialog(context),
                        child: const Center(
                          child: Text(
                            'Set Alarm',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: MediaQuery.of(context).size.width * 0.15,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.amber, Colors.orangeAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => WatchMarketPage()),
                        ),
                        child: const Center(
                          child: Text(
                            'Watch Market',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // Sağ taraf: Followed
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.grey.shade900, Colors.grey.shade800],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amberAccent, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.7),
                      blurRadius: 10,
                      offset: const Offset(2, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    children: [
                      Center(
                        child: Text(
                          "Followed",
                          style: TextStyle(
                            color: Colors.amber.shade400,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                offset: const Offset(1.5, 1.5),
                                blurRadius: 4,
                                color: Colors.black87,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Divider(color: Colors.amber.shade400, thickness: 1.2),
                      Expanded(
                        child: _loading
                            ? const Center(
                                child: CircularProgressIndicator(color: Colors.amber))
                            : _followedItems.isEmpty
                                ? const Center(
                                    child: Text(
                                      "No alarms yet",
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _followedItems.length,
                                    itemBuilder: (context, index) {
                                      final item = _followedItems[index];
                                      final displayText =
                                          "${index + 1}. ${item['symbol']} - %${item['percentage']}";

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: AnimatedSlide(
                                          duration: const Duration(milliseconds: 500),
                                          curve: Curves.easeInOut,
                                          offset: _isDeleted[item['id']] == true
                                              ? const Offset(-1.5, 0)
                                              : Offset.zero,
                                          child: Slidable(
                                            key: ValueKey(item['id']),
                                            startActionPane: ActionPane(
                                              motion: const DrawerMotion(),
                                              extentRatio: 0.15,
                                              children: [
                                                CustomSlidableAction(
                                                  onPressed: (context) {
                                                    _openEditAlarmDialog(context, item);
                                                  },
                                                  backgroundColor: Colors.blueAccent.shade700,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  borderRadius: BorderRadius.circular(4),
                                                  child: const Icon(Icons.edit,
                                                      size: 32, color: Colors.white),
                                                ),
                                              ],
                                            ),
                                            endActionPane: ActionPane(
                                              motion: const DrawerMotion(),
                                              extentRatio: 0.15,
                                              children: [
                                                CustomSlidableAction(
                                                  onPressed: (context) async {
                                                    setState(() {
                                                      _isDeleted[item['id']] = true;
                                                    });
                                                    await Future.delayed(
                                                        const Duration(milliseconds: 500));
                                                    await _deleteAlarm(item['id']);
                                                    setState(() {
                                                      _followedItems.removeWhere(
                                                          (e) => e['id'] == item['id']);
                                                      _isDeleted.remove(item['id']);
                                                    });
                                                  },
                                                  backgroundColor: Colors.red.shade700,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  borderRadius: BorderRadius.circular(4),
                                                  child: const Icon(Icons.delete,
                                                      size: 32, color: Colors.white),
                                                ),
                                              ],
                                            ),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [Colors.grey.shade900, Colors.grey.shade800],
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                ),
                                                borderRadius: BorderRadius.circular(4),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.6),
                                                    blurRadius: 6,
                                                    offset: const Offset(2, 2),
                                                  ),
                                                ],
                                              ),
                                              child: InkWell(
                                                onTap: () => _openEditAlarmDialog(context, item),
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                                  child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.center,
                                                    children: [
                                                      // Leading Icon
                                                      Container(
                                                        width: 40, // Genişlik sınırı
                                                        height: 40, // Yükseklik sınırı
                                                        decoration: BoxDecoration(
                                                          color: Colors.amber.shade600.withOpacity(0.3),
                                                          shape: BoxShape.circle,
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: Colors.amber.withOpacity(0.5),
                                                              blurRadius: 6,
                                                              spreadRadius: 1,
                                                            ),
                                                          ],
                                                        ),
                                                        padding: const EdgeInsets.all(6),
                                                        child: const Icon(
                                                          Icons.notifications_active,
                                                          color: Colors.amber,
                                                          size: 28,
                                                        ),
                                                      ),

                                                      const SizedBox(width: 12), // Leading ile title arası boşluk

                                                      // Title Text
                                                      Expanded(
                                                        child: Text(
                                                          displayText,
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight: FontWeight.w600,
                                                            fontSize: 14,
                                                            shadows: [
                                                              Shadow(
                                                                offset: Offset(0.8, 0.8),
                                                                blurRadius: 2,
                                                                color: Colors.black54,
                                                              ),
                                                            ],
                                                          ),
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
                                    },
                                  ),
                      ),
                    ],
                  ),
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

class _WatchMarketPageState extends State<WatchMarketPage> {
  final String backendBaseUrl = "http://192.168.0.104:8000"; // Backend URL
  Map<String, List<Map<String, dynamic>>> marketData = {
    "BIST": [],
    "NASDAQ": [],
    "CRYPTO": [],
    "METALS": [],
  };
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchAllMarkets();
  }

  Future<void> fetchAllMarkets() async {
    setState(() => loading = true);
    try {
      final responses = await Future.wait([
        http.get(Uri.parse("$backendBaseUrl/symbols_with_name?market=BIST")),
        http.get(Uri.parse("$backendBaseUrl/symbols_with_name?market=NASDAQ")),
        http.get(Uri.parse("$backendBaseUrl/symbols_with_name?market=CRYPTO")),
        http.get(Uri.parse("$backendBaseUrl/metals")),
      ]);

      final bistSymbolsRes = responses[0];
      final nasdaqSymbolsRes = responses[1];
      final cryptoSymbolsRes = responses[2];
      final metalsRes = responses[3];

      if (bistSymbolsRes.statusCode == 200) {
        List<dynamic> list = jsonDecode(bistSymbolsRes.body);
        marketData["BIST"] = list.map<Map<String, dynamic>>((e) {
          return {
            "symbol": e['symbol'] ?? '',
            "name": e['name'] ?? e['symbol'] ?? '',
            "price": null,
          };
        }).toList();
      }

      if (nasdaqSymbolsRes.statusCode == 200) {
        List<dynamic> list = jsonDecode(nasdaqSymbolsRes.body);
        marketData["NASDAQ"] = list.map<Map<String, dynamic>>((e) {
          return {
            "symbol": e['symbol'] ?? '',
            "name": e['name'] ?? e['symbol'] ?? '',
            "price": null,
          };
        }).toList();
      }

      if (cryptoSymbolsRes.statusCode == 200) {
        List<dynamic> list = jsonDecode(cryptoSymbolsRes.body);
        marketData["CRYPTO"] = list.map<Map<String, dynamic>>((e) {
          return {
            "symbol": e['symbol'] ?? '',
            "name": e['name'] ?? e['symbol'] ?? '',
            "price": null,
          };
        }).toList();
      }

      if (metalsRes.statusCode == 200) {
        Map<String, dynamic> metalsMap = jsonDecode(metalsRes.body);
        marketData["METALS"] = metalsMap.entries.map<Map<String, dynamic>>((e) {
          final priceValue = e.value;
          double? price;
          if (priceValue != null && (priceValue is num)) {
            price = priceValue.toDouble();
          }
          return {
            "symbol": e.key,
            "name": e.key,
            "price": price,
          };
        }).toList();
      }

      // Şimdi fiyatları ayrı endpointten çekip güncelleyelim
      await fetchAllPrices();

    } catch (e) {
      print("Error fetching market data: $e");
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> fetchAllPrices() async {
    try {
      final res = await http.get(Uri.parse("$backendBaseUrl/prices"));
      if (res.statusCode == 200) {
        List<dynamic> pricesList = jsonDecode(res.body);
        Map<String, double?> priceMap = {};
        for (var p in pricesList) {
          if (p['symbol'] != null) {
            final key = p['symbol'];
            final priceValue = p['price'];
            double? price;
            if (priceValue != null && priceValue is num) {
              price = priceValue.toDouble();
            }
            priceMap[key] = price;
          }
        }

        // Fiyatları marketData ile eşleştir
        marketData.forEach((market, list) {
          for (var item in list) {
            final sym = item['symbol'];
            if (sym != null && priceMap.containsKey(sym)) {
              item['price'] = priceMap[sym];
            }
          }
        });
      }
    } catch (e) {
      print("Error fetching prices: $e");
    } finally {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.amber),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Watch Market 📈', style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 22, letterSpacing: 1.5, shadows: [Shadow(offset: Offset(1,1), blurRadius: 3, color: Colors.black54)])),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        marketColumn("BIST"),
                        marketColumn("NASDAQ"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      children: [
                        marketColumn("CRYPTO"),
                        marketColumn("METALS"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
  Widget marketColumn(String market) {
  final data = marketData[market] ?? [];

  // Fiyatı null veya 0 olanları filtrele
  final filteredData = data.where((item) {
    final priceValue = item['price'];
    return priceValue != null && priceValue is num && priceValue > 0;
  }).toList();

  return Expanded(
    child: Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey.shade900, Colors.grey.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Market başlığı
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.amber, Colors.deepOrangeAccent],
                ).createShader(bounds),
                child: Text(
                  market,
                  style: const TextStyle(
                    color: Colors.white, // ShaderMask üstüne uygulanacak
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
          Divider(color: Colors.amber.shade300, thickness: 1),

          // Sütun başlıkları
          Row(
            children: const [
              Expanded(
                flex: 2,
                child: Center(
                  child: Text("Symbol",
                      style: TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
              ),
              Expanded(
                flex: 5,
                child: Center(
                  child: Text("Name",
                      style: TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text("Price",
                      style: TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
              ),
            ],
          ),
          Divider(color: Colors.amber.shade300, thickness: 0.8),

          // Liste
          Expanded(
            child: filteredData.isEmpty
                ? const Center(
                    child: Text("No data",
                        style: TextStyle(color: Colors.white70)),
                  )
                : ListView.builder(
                    itemCount: filteredData.length,
                    itemBuilder: (context, index) {
                      final item = filteredData[index];
                      final priceValue = item['price'];

                      // Market bazlı simge ekleme
                      String currencySymbol;
                      if (market == "BIST" || market == "METALS") {
                        currencySymbol = "₺";
                      } else {
                        currencySymbol = "\$";
                      }

                      final displayPrice = "$priceValue$currencySymbol";

                      // Metals için özel name
                      String displayName = item['name'] ?? item['symbol'] ?? '';
                      if (market == "METALS") {
                        displayName = "Gram $displayName";
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: index % 2 == 0
                              ? Colors.black.withOpacity(0.05)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 4),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Center(
                                  child: Text(item['symbol'] ?? '',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500)),
                                ),
                              ),
                              Expanded(
                                flex: 5,
                                child: Center(
                                  child: Text(displayName,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14)),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Center(
                                  child: Text(displayPrice,
                                      style: const TextStyle(
                                          color: Colors.amber,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
 }
}