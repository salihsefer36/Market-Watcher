import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// Your backend URL (change with your own IP for local testing)
const String backendBaseUrl = "http://192.168.0.104:8000";

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true; // Default value
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _isLoading = false);
        return;
      }
      
      final uri = Uri.parse("$backendBaseUrl/user/settings/$uid");
      final response = await http.get(uri);

      if (response.statusCode == 200 && mounted) {
        final settings = jsonDecode(response.body);
        setState(() {
          _notificationsEnabled = settings['notifications_enabled'];
        });
      }
    } catch (e) {
      print("Failed to load settings: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveNotificationSettings(bool newValue) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final uri = Uri.parse("$backendBaseUrl/user/settings/$uid");
      final body = jsonEncode({'notifications_enabled': newValue});
      
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode != 200 && mounted) {
        setState(() => _notificationsEnabled = !newValue);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save setting. Please try again.'))
        );
      }
    } catch (e) {
      print("Failed to save settings: $e");
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black,
        title: Text('Settings', style: TextStyle(color: Colors.white, fontSize: 20.sp)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.amber),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : ListView(
              padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 16.w),
              children: [
                _buildSectionHeader('General'),
                _buildSettingsCard(
                  children: [
                    _buildLanguageTile(),
                    _buildNotificationsTile(),
                  ],
                ),
                SizedBox(height: 30.h),
                _buildSectionHeader('Account'),
                _buildSettingsCard(
                  children: [
                    _buildSignOutTile(),
                  ],
                ),
                SizedBox(height: 30.h),
                Center(
                  child: Text(
                    'Market Watcher v1.0.0',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12.sp),
                  ),
                )
              ],
            ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h, left: 8.w),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 12.sp,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildLanguageTile() {
    return ListTile(
      leading: const Icon(Icons.language_outlined, color: Colors.amber),
      title: const Text('Application Language', style: TextStyle(color: Colors.white)),
      subtitle: Text('English', style: TextStyle(color: Colors.grey.shade400)),
      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Language change feature will be added soon.')),
        );
      },
    );
  }

  Widget _buildNotificationsTile() {
    return SwitchListTile.adaptive(
      secondary: const Icon(Icons.notifications_active_outlined, color: Colors.amber),
      title: const Text('Notifications', style: TextStyle(color: Colors.white)),
      subtitle: Text('For all alarms', style: TextStyle(color: Colors.grey.shade400)),
      value: _notificationsEnabled,
      activeColor: Colors.amber,
      onChanged: _isSaving ? null : (bool value) {
        setState(() => _notificationsEnabled = value);
        _saveNotificationSettings(value);
      },
    );
  }
  
  Widget _buildSignOutTile() {
    return ListTile(
      leading: Icon(Icons.logout, color: Colors.red.shade400),
      title: Text('Sign Out', style: TextStyle(color: Colors.red.shade400)),
      onTap: () async {
        Navigator.pop(context);
        await FirebaseAuth.instance.signOut();
        await GoogleSignIn().signOut();
      },
    );
  }
}