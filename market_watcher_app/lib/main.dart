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
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black,
        primarySwatch: Colors.amber,
        cardTheme: CardThemeData(
          color: Colors.grey[900],
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
          hintStyle: TextStyle(color: Colors.grey),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white),
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
      body: Center(
        child: Card(
          color: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 8,
          margin: const EdgeInsets.symmetric(horizontal: 32),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Market Watcher',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD700),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  icon: Image.asset('assets/images/google_logo.png', height: 24, width: 24),
                  label: const Text('Google ile Giriş Yap'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Color(0xFFFFD700),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    final userCredential = await signInWithGoogle();
                    if (userCredential != null) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => HomePage()),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Giriş başarısız')),
                      );
                    }
                  },
                ),
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
  final List<Map<String, dynamic>> _followedItems = [];
  final String backendBaseUrl = "http://localhost:8000"; // backend URL

  // Backend'den market sembollerini çek
  Future<List<String>> _fetchSymbolsForMarket(String market) async {
    try {
      final uri = Uri.parse("$backendBaseUrl/symbols?market=$market");
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.map((e) => e.toString()).toList();
      }
    } catch (e) {
      print("Error fetching symbols for $market: $e");
    }
    return [];
  }

  // Backend'den tüm fiyatları çek
  Future<List<Map<String, dynamic>>> _fetchAllPrices() async {
    try {
      final uri = Uri.parse("$backendBaseUrl/prices");
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      print("Error fetching prices: $e");
    }
    return [];
  }

  // Set Alarm dialog'u
  void _openSetAlarmDialog(BuildContext context,
      {Map<String, dynamic>? editItem, int? index}) async {
    String? selectedMarket = editItem?['market'];
    String? selectedSymbol = editItem?['symbol'];
    double? selectedPercentage = editItem?['percentage'];

    final markets = ['BIST', 'NASDAQ', 'CRYPTO', 'METALS'];
    final percentages = [1, 2, 5, 10];

    List<String> symbolsForMarket = [];
    if (selectedMarket != null) {
      symbolsForMarket = await _fetchSymbolsForMarket(selectedMarket);
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            editItem == null ? 'Set Alarm' : 'Edit Alarm',
            style: const TextStyle(color: Colors.amber),
          ),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    dropdownColor: Colors.grey[850],
                    hint: const Text('Select Market',
                        style: TextStyle(color: Colors.white)),
                    value: selectedMarket,
                    items: markets
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m,
                                  style: const TextStyle(color: Colors.white)),
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
                  const SizedBox(height: 12),
                  if (selectedMarket != null)
                    DropdownButton<String>(
                      dropdownColor: Colors.grey[850],
                      hint: const Text('Select Symbol',
                          style: TextStyle(color: Colors.white)),
                      value: selectedSymbol,
                      items: symbolsForMarket
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s,
                                    style: const TextStyle(
                                        color: Colors.white)),
                              ))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => selectedSymbol = value),
                    ),
                  const SizedBox(height: 12),
                  DropdownButton<double>(
                    dropdownColor: Colors.grey[850],
                    hint: const Text('Select Change %',
                        style: TextStyle(color: Colors.white)),
                    value: selectedPercentage,
                    items: percentages
                        .map((p) => DropdownMenuItem(
                              value: p.toDouble(),
                              child: Text('$p%',
                                  style: const TextStyle(color: Colors.white)),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedPercentage = value),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () {
                if (selectedMarket != null &&
                    selectedSymbol != null &&
                    selectedPercentage != null) {
                  final exists = _followedItems.any((item) =>
                      item['market'] == selectedMarket &&
                      item['symbol'] == selectedSymbol &&
                      (index == null || _followedItems.indexOf(item) != index));

                  if (exists) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("This alarm already exists!"),
                      backgroundColor: Colors.red,
                    ));
                    return;
                  }

                  final newItem = {
                    "market": selectedMarket,
                    "symbol": selectedSymbol,
                    "percentage": selectedPercentage,
                  };

                  setState(() {
                    if (index != null) {
                      _followedItems[index] = newItem;
                    } else {
                      _followedItems.add(newItem);
                    }
                  });

                  Navigator.pop(context);
                }
              },
              child: Text(editItem == null ? 'Set' : 'Update',
                  style: const TextStyle(color: Colors.amber)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    // UI kodu değişmedi
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Market Watcher - ${user?.displayName ?? user?.email ?? ''}',
          style: const TextStyle(color: Color(0xFFFFD700)),
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
            // Sol taraf: Butonlar
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () => _openSetAlarmDialog(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[700],
                      foregroundColor: Colors.black,
                      minimumSize: const Size(150, 60),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Set Alarm',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => WatchMarketPage()),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[700],
                      foregroundColor: Colors.black,
                      minimumSize: const Size(150, 60),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Watch Market',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // Sağ taraf: Followed Panel
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber, width: 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    children: [
                      const Center(
                        child: Text(
                          "Followed",
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Divider(color: Colors.amber),
                      Expanded(
                        child: _followedItems.isEmpty
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
                                      "${index + 1}. ${item['market']} - ${item['symbol']} - ${item['percentage']}%";

                                  item.putIfAbsent('isDeleting', () => false);

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Slidable(
                                      key: ValueKey(displayText),
                                      endActionPane: ActionPane(
                                        motion: const DrawerMotion(),
                                        extentRatio: 0.15,
                                        children: [
                                          CustomSlidableAction(
                                            onPressed: (context) {
                                              setState(() {
                                                _followedItems[index]['isDeleting'] = true;
                                              });
                                              Future.delayed(const Duration(milliseconds: 500), () {
                                                final removedItem = _followedItems[index];
                                                setState(() {
                                                  _followedItems.removeAt(index);
                                                });
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                        '${removedItem['market']} ${removedItem['symbol']} deleted'),
                                                    duration: const Duration(milliseconds: 800),
                                                  ),
                                                );
                                              });
                                            },
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            borderRadius: BorderRadius.circular(2),
                                            child: Icon(Icons.delete, size: 32, color: Colors.white),
                                          ),
                                        ],
                                      ),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 500),
                                        curve: Curves.easeInOut,
                                        transform: item['isDeleting']
                                            ? Matrix4.translationValues(-500, 0, 0)
                                            : Matrix4.identity(),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.grey[850],
                                            borderRadius: BorderRadius.circular(2),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.6),
                                                blurRadius: 6,
                                                offset: const Offset(2, 2),
                                              ),
                                            ],
                                          ),
                                          child: ListTile(
                                            dense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                            leading: const Icon(Icons.notifications_active, color: Colors.amber, size: 28),
                                            title: Text(
                                              displayText,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w500,
                                                fontSize: 14,
                                              ),
                                            ),
                                            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
                                            onTap: () {
                                              _openSetAlarmDialog(context, editItem: item, index: index);
                                            },
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
  final String backendBaseUrl = "http://127.0.0.1:8000"; // Backend URL
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
        title: const Text('Watch Market', style: TextStyle(color: Color(0xFFFFD700))),
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
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber),
        ),
        child: Column(
          children: [
            // Market başlığı
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Center(
                child: Text(
                  market,
                  style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
            ),
            const Divider(color: Colors.amber),
            // Sütun başlıkları
            Row(
              children: const [
                Expanded(flex: 2, child: Center(child: Text("Symbol", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)))),
                Expanded(flex: 5, child: Center(child: Text("Name", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)))),
                Expanded(flex: 2, child: Center(child: Text("Price", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)))),
              ],
            ),
            const Divider(color: Colors.amber),
            // Liste
            Expanded(
              child: data.isEmpty
                  ? const Center(child: Text("No data", style: TextStyle(color: Colors.white70)))
                  : ListView.builder(
                      itemCount: data.length,
                      itemBuilder: (context, index) {
                        final item = data[index];
                        final priceValue = item['price'];
                        String displayPrice = (priceValue != null && priceValue is num)
                            ? priceValue.toString()
                            : 'N/A';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Center(child: Text(item['symbol'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14)))),
                              Expanded(flex: 5, child: Center(child: Text(item['name'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 14)))),
                              Expanded(flex: 2, child: Center(child: Text(displayPrice, style: const TextStyle(color: Colors.amber, fontSize: 14)))),
                            ],
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