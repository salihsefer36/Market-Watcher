import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageSate();
}

class _SettingsPageSate extends State<SettingsPage> {
  bool _notificationsEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black,
        title: Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontSize: 20.sp),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.amber),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
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

          // --- Application Info ---
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
      child: Column(
        children: children,
      ),
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

  // Dil ayarı için ListTile
  Widget _buildLanguageTile() {
    return ListTile(
      leading: const Icon(Icons.language_outlined, color: Colors.amber),
      title: const Text('Application Language', style: TextStyle(color: Colors.white)),
      subtitle: Text('English', style: TextStyle(color: Colors.grey.shade400)),
      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
      onTap: () {
        // TODO: Dil değiştirme diyalogu burada açılabilir.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dil değiştirme özelliği yakında eklenecek.')),
        );
      },
    );
  }

  // Bildirim ayarı için ListTile
  Widget _buildNotificationsTile() {
    return SwitchListTile.adaptive(
      secondary: const Icon(Icons.notifications_active_outlined, color: Colors.amber),
      title: const Text('Notifications', style: TextStyle(color: Colors.white)),
      subtitle: Text('For all alarms', style: TextStyle(color: Colors.grey.shade400)),
      value: _notificationsEnabled,
      activeColor: Colors.amber,
      onChanged: (bool value) {
        setState(() {
          _notificationsEnabled = value;
          // TODO: Backend'e bildirim ayarını kaydetme veya
          // cihazdan FCM token aboneliğini kaldırma işlemi burada yapılabilir.
        });
      },
    );
  }
  
  Widget _buildSignOutTile() {
    return ListTile(
      leading: Icon(Icons.logout, color: Colors.red.shade400),
      title: Text('Log Out', style: TextStyle(color: Colors.red.shade400)),
      onTap: () async {
        Navigator.pop(context); 
        
        await FirebaseAuth.instance.signOut();
        await GoogleSignIn().signOut();
      },
    );
  }
}