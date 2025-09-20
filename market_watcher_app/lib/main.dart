import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart';

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
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
       return const HomePage();
      },
    );
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

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
      body: Container(
        color: Colors.black,
        child: Center(
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
                    icon: Image.asset(
                      'assets/images/google_logo.png',
                      height: 24,
                      width: 24,
                    ),
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
                          MaterialPageRoute(builder: (_) => const HomePage()),
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
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final TextEditingController _dataController = TextEditingController();

  static const String backendUrl = "http://192.168.0.104:8000";

  List<Map<String, dynamic>> bistList = [];
  List<Map<String, dynamic>> nasdaqList = [];
  List<Map<String, dynamic>> cryptoList = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _requestPermission();
    _saveDeviceToken();
    _fetchMarketLists();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message.notification!.title ?? 'Bildirim geldi!')),
        );
      }
    });
  }

  Future<void> _requestPermission() async => await _messaging.requestPermission();

  Future<void> _saveDeviceToken() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final token = await _messaging.getToken();
    if (token != null) {
      await _firestore.collection('user_tokens').doc(user.uid).set({
        'token': token,
        'email': user.email,
      });
    }
  }

    Future<void> _fetchMarketLists() async {
    setState(() => loading = true);
    try {
      final responses = await Future.wait([
        http.get(Uri.parse("$backendUrl/bist_prices")).timeout(const Duration(seconds: 15)),
        http.get(Uri.parse("$backendUrl/nasdaq_prices?n=10")).timeout(const Duration(seconds: 15)),
        http.get(Uri.parse("$backendUrl/crypto_prices?n=10")).timeout(const Duration(seconds: 15)),
      ]);

        setState(() {
        bistList = List<Map<String, dynamic>>.from(json.decode(responses[0].body));
        nasdaqList = List<Map<String, dynamic>>.from(json.decode(responses[1].body));
        cryptoList = List<Map<String, dynamic>>.from(json.decode(responses[2].body));
        loading = false;
      });
    } catch (e) {
      print("Market list fetch error: $e");
      setState(() => loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Veriler alınamadı, lütfen tekrar deneyin.")),
        );
      }
    }
  }


  Future<void> addData() async {
    final user = _auth.currentUser;
    if (user == null || _dataController.text.isEmpty) return;

    final message = _dataController.text;
    await _firestore.collection('market_data').add({
      'user': user.email,
      'data': message,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _dataController.clear();

    try {
      final tokenDoc = await _firestore.collection('user_tokens').doc(user.uid).get();
      final token = tokenDoc.data()?['token'];
      if (token == null) return;

      final body = json.encode({
        'symbol': 'CUSTOM',
        'threshold': 0,
        'direction': 'above',
        'message': message,
        'user_token': token,
      });

      final res = await http.post(
        Uri.parse("$backendUrl/alerts"),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (res.statusCode == 200) print("Backend alert kaydedildi");
    } catch (e) {
      print("Backend request hatası: $e");
    }
  }

Widget _buildList(String title, List<Map<String, dynamic>> list) {
  return Card(
    color: Colors.grey[900],
    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    child: ExpansionTile(
      title: Text(title, style: const TextStyle(color: Color(0xFFFFD700))),
      children: list
          .map((item) => ListTile(
                title: Text(item['symbol'], style: const TextStyle(color: Colors.white)),
                subtitle: Text(item['price'] != null ? item['price'].toString() : "Veri yok",
                    style: const TextStyle(color: Colors.grey)),
              ))
          .toList(),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('Market Watcher - ${user?.displayName ?? user?.email ?? ''}',
            style: const TextStyle(color: Color(0xFFFFD700))),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFFFD700)),
            onPressed: () async {
              await _auth.signOut();
              await GoogleSignIn().signOut();
            },
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : Column(
              children: [
                // Veri ekleme kartı
                Card(
                  color: Colors.grey[900],
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _dataController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Yeni veri ekle...',
                              hintStyle: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send, color: Color(0xFFFFD700)),
                          onPressed: addData,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      _buildList("BIST Companies", bistList),
                      _buildList("NASDAQ Companies", nasdaqList),
                      _buildList("Cryptocurrencies", cryptoList),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}