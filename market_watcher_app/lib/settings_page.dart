import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';
import 'locale_provider.dart';
import 'main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isInit = true;
  bool _notificationsEnabled = true;
  String _currentLanguageCode = 'en';

  final Map<String, String> _supportedLanguages = {
    'en': 'English', 'tr': 'Türkçe', 'de': 'Deutsch', 'fr': 'Français', 'es': 'Español',
    'it': 'Italiano', 'ru': 'Русский', 'zh': '中文 (简体)', 'hi': 'हिन्दी', 'ja': '日本語', 'ar': 'العربية',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
      _currentLanguageCode = localeProvider.locale.languageCode;
      _loadSettings();
      _isInit = false;
    }
  }

  Future<void> _loadSettings() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final uri = Uri.parse("$backendBaseUrl/user/settings/$uid");
      final response = await http.get(uri);

      if (response.statusCode == 200 && mounted) {
        final settings = jsonDecode(response.body);
        setState(() {
          _notificationsEnabled = settings['notifications_enabled'];
          _currentLanguageCode = settings['language_code'] ?? 'en';
        });
        // Uygulamanın genel dilini başlangıçta ayarla
        Provider.of<LocaleProvider>(context, listen: false).setLocale(_currentLanguageCode);
      }
    } catch (e) {
      print("Failed to load settings: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSettings({bool? notifications, String? langCode}) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final uri = Uri.parse("$backendBaseUrl/user/settings/$uid");
      final body = jsonEncode({
        'notifications_enabled': notifications ?? _notificationsEnabled,
        'language_code': langCode ?? _currentLanguageCode
      });

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode != 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save settings.')));
        await _loadSettings();
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
    final localizations = AppLocalizations.of(context)!;

    return Container(
      // Ana ekran arka planı gradyanı eklendi
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.grey.shade900, Colors.black], begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          title: Text(localizations.settings, style: TextStyle(color: Colors.white, fontSize: 22.sp, fontWeight: FontWeight.bold)),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.amber.shade400),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: Colors.amber.shade400))
            : ListView(
                padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 16.w),
                children: [
                  _buildSectionHeader(localizations.general),
                  _buildSettingsCard(
                    children: [
                      _buildLanguageTile(localizations),
                      const Divider(color: Color(0xFF333333), height: 1, indent: 16, endIndent: 16),
                      _buildNotificationsTile(localizations),
                    ],
                  ),
                  SizedBox(height: 30.h),
                  _buildSectionHeader(localizations.account),
                  _buildSettingsCard(
                    children: [
                      _buildSignOutTile(localizations),
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
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    // Ayarlar kartına belirgin bir gölge ve border eklendi
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.amber.withOpacity(0.2), width: 1.0),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h, left: 8.w, top: 12.h),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.amber.shade400, // Başlık rengi amber yapıldı
          fontSize: 14.sp,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildLanguageTile(AppLocalizations localizations) {
    return ListTile(
      leading: Icon(Icons.language_outlined, color: Colors.amber.shade400),
      title: const Text('Uygulama Dili', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(
        _supportedLanguages[_currentLanguageCode] ?? 'English',
        style: TextStyle(color: Colors.grey.shade400),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
      onTap: () => _showLanguageDialog(localizations),
    );
  }

  Widget _buildNotificationsTile(AppLocalizations localizations) {
    return SwitchListTile.adaptive(
      secondary: Icon(Icons.notifications_active_outlined, color: Colors.amber.shade400),
      title: Text(localizations.notifications, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(localizations.forAllAlarms, style: TextStyle(color: Colors.grey.shade400)),
      value: _notificationsEnabled,
      activeColor: Colors.amber.shade400,
      onChanged: _isSaving ? null : (bool value) {
        setState(() => _notificationsEnabled = value);
        _saveSettings(notifications: value);
      },
    );
  }
  
  Widget _buildSignOutTile(AppLocalizations localizations) {
    return ListTile(
      leading: Icon(Icons.logout, color: Colors.red.shade400),
      title: Text(localizations.signOut, style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w600)),
      onTap: () async {
        Navigator.pop(context);
        await FirebaseAuth.instance.signOut();
        await GoogleSignIn().signOut();
      },
    );
  }

  void _showLanguageDialog(AppLocalizations localizations) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: Text(localizations.applicationLanguage, style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _supportedLanguages.entries.map((entry) {
                  final isSelected = _currentLanguageCode == entry.key;
                  return ListTile(
                    title: Text(entry.value, style: TextStyle(color: isSelected ? Colors.amber.shade400 : Colors.white)),
                    trailing: isSelected ? Icon(Icons.check, color: Colors.amber.shade400) : null,
                    onTap: () => _onLanguageSelected(entry.key),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(localizations.cancel, style: TextStyle(color: Colors.amber.shade400)),
            )
          ],
        );
      },
    );
  }

  void _onLanguageSelected(String langCode) {
    Provider.of<LocaleProvider>(context, listen: false).setLocale(langCode);
    
    setState(() => _currentLanguageCode = langCode);
    
    _saveSettings(langCode: langCode);
    
    Navigator.pop(context);
  }
}