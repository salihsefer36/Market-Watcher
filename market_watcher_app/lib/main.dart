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
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
        if (snapshot.hasData) {
          return const HomePage();
        } else {
          return const LoginPage();
        }
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
      appBar: AppBar(title: const Text('Google ile Giriş')),
      body: Center(
        child: ElevatedButton.icon(
          icon: Image.asset(
         'assets/images/google_logo.png',
          height: 24,    
          width: 24,
        ),
          label: const Text('Google ile Giriş Yap'),
          style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white, // Beyaz arka plan Google butonu için
          foregroundColor: Colors.black,  // Yazı rengi siyah
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
        onPressed: () async {
          final userCredential = await signInWithGoogle();
            if (userCredential != null) {
              Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const HomePage()));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Giriş başarısız')));
            }
          },
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

  // Emulator için localhost: 10.0.2.2
  static const String backendUrl = "http://10.0.2.2:8000/alerts";

  @override
  void initState() {
    super.initState();
    _requestPermission();
    _saveDeviceToken();
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(message.notification!.title ?? 'Bildirim geldi!')));
      }
    });
  }

  Future<void> _requestPermission() async {
    await _messaging.requestPermission();
  }

  Future<void> _saveDeviceToken() async {
    final user = _auth.currentUser;
    if (user == null) return;

    String? token = await _messaging.getToken();
    if (token != null) {
      await _firestore.collection('user_tokens').doc(user.uid).set({
        'token': token,
        'email': user.email,
      });
    }
  }

  Future<void> addData() async {
    final user = _auth.currentUser;
    if (user == null || _dataController.text.isEmpty) return;

    final message = _dataController.text;

    // Firestore'a kaydet
    await _firestore.collection('market_data').add({
      'user': user.email,
      'data': message,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _dataController.clear();

    // Backend'e POST et
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

      final res = await http.post(Uri.parse(backendUrl),
          headers: {'Content-Type': 'application/json'}, body: body);

      if (res.statusCode == 200) {
        print("Backend alert kaydedildi");
      } else {
        print("Backend alert hatası: ${res.body}");
      }
    } catch (e) {
      print("Backend request hatası: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: Text('Market Watcher - ${user?.displayName ?? user?.email ?? ''}'),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await _auth.signOut();
                await GoogleSignIn().signOut();
              }),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dataController,
                    decoration: const InputDecoration(labelText: 'Veri ekle'),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: addData)
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('market_data')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text(data['data'] ?? ''),
                      subtitle: Text(data['user'] ?? ''),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}