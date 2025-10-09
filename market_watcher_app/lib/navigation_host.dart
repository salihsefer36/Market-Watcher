import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'alarms_page.dart';
import 'watch_market_page.dart';
import 'subscriptions_page.dart';
import 'settings_page.dart';
import 'l10n/app_localizations.dart';

class NavigationHostPage extends StatefulWidget {
  const NavigationHostPage({super.key});

  @override
  State<NavigationHostPage> createState() => _NavigationHostPageState();
}

class _NavigationHostPageState extends State<NavigationHostPage> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    AlarmsPage(),
    WatchMarketPage(),
    SubscriptionsPage(),
    SettingsPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;

    // DEĞİŞTİ: Başlıklar dinamik hale getirildi.
    final pageTitles = [
      user?.displayName ?? localizations.marketWatcher, // Alarmlar sayfasında kullanıcı adı gösterilecek
      localizations.watchMarkets,
      localizations.subscriptions,
      localizations.settings,
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey.shade900, Colors.black],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          // DEĞİŞTİ: Artık başlık seçili sekmeye göre değişiyor
          title: Text(
            pageTitles[_selectedIndex],
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22.sp,
            ),
          ),
          // DEĞİŞTİ: Sağ üstteki "+" butonu buradan kaldırıldı.
          actions: null, 
        ),
        body: Center(
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: const Icon(Icons.notifications_active_outlined),
              label: localizations.alarms,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.bar_chart_rounded),
              label: localizations.markets,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.workspace_premium_outlined),
              label: localizations.subscriptions,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              label: localizations.settings,
            ),
          ],
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          backgroundColor: Colors.grey.shade900.withOpacity(0.8),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.amber.shade400,
          unselectedItemColor: Colors.grey.shade600,
          selectedFontSize: 12.sp,
          unselectedFontSize: 12.sp,
        ),
      ),
    );
  }
}