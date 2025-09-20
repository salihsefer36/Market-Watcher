import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

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

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
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

                                  // Silinecek mi kontrolü için flag ekliyoruz
                                  item.putIfAbsent('isDeleting', () => false);

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Slidable(
                                      key: ValueKey(displayText),
                                      endActionPane: ActionPane(
                                        motion: const DrawerMotion(),
                                        extentRatio: 0.22,
                                        children: [
                                          CustomSlidableAction(
                                            onPressed: (context) {
                                              setState(() {
                                                _followedItems[index]['isDeleting'] = true;
                                              });
                                              // 0.5 saniye sonra tamamen sil
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
                                        child: ListTile(
                                          dense: true,
                                          title: Center(
                                            child: Text(
                                              displayText,
                                              style: const TextStyle(color: Colors.white),
                                            ),
                                          ),
                                          onTap: () {
                                            _openSetAlarmDialog(context,
                                                editItem: item, index: index);
                                          },
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

  void _openSetAlarmDialog(BuildContext context,
      {Map<String, dynamic>? editItem, int? index}) {
    showDialog(
      context: context,
      builder: (context) {
        String? selectedMarket = editItem?['market'];
        String? selectedSymbol = editItem?['symbol'];
        double? selectedPercentage = editItem?['percentage'];

        final markets = ['BIST', 'NASDAQ', 'CRYPTO', 'METALS'];
        final percentages = [1, 2, 5, 10];

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
                    onChanged: (value) {
                      setState(() {
                        selectedMarket = value;
                        selectedSymbol = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (selectedMarket != null)
                    DropdownButton<String>(
                      dropdownColor: Colors.grey[850],
                      hint: const Text('Select Symbol',
                          style: TextStyle(color: Colors.white)),
                      value: selectedSymbol,
                      items: _getSymbolsForMarket(selectedMarket!)
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

  List<String> _getSymbolsForMarket(String market) {
    switch (market) {
      case 'BIST':
        return ['THYAO', 'ASELS', 'GARAN', 'AKBNK'];
      case 'NASDAQ':
        return ['TSLA', 'NVDA', 'AAPL', 'MSFT'];
      case 'CRYPTO':
        return ['BTCUSDT', 'ETHUSDT', 'BNBUSDT'];
      case 'METALS':
        return ['Gold', 'Silver', 'Copper'];
      default:
        return [];
    }
  }
}

class WatchMarketPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.amber),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Watch Market',
            style: TextStyle(color: Color(0xFFFFD700))),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: const Center(
        child: Text('Market prices will appear here',
            style: TextStyle(color: Colors.white)),
      ),
    );
  }
}