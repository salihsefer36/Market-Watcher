// navigation_host.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'alarms_page.dart';
import 'watch_market_page.dart';
import 'subscriptions_page.dart';
import 'settings_page.dart';
import 'l10n/app_localizations.dart';

// DEĞİŞTİ: animated_bottom_navigation_bar import'u kaldırıldı.

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

  final iconList = <IconData>[
    Icons.notifications_active_outlined,
    Icons.bar_chart_rounded,
    Icons.workspace_premium_outlined,
    Icons.settings_outlined,
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

    final pageTitles = [
      user?.displayName ?? localizations.marketWatcher,
      localizations.watchMarkets,
      localizations.subscriptions,
      localizations.settings,
    ];

    final pageLabels = [
      localizations.alarms,
      localizations.markets,
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
          title: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, -0.5),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              pageTitles[_selectedIndex],
              key: ValueKey<int>(_selectedIndex),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22.sp,
              ),
            ),
          ),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          child: Container(
            key: ValueKey<int>(_selectedIndex),
            child: _widgetOptions.elementAt(_selectedIndex),
          ),
        ),
        // DEĞİŞTİ: Standart BottomNavigationBar'a geri döndük ve onu özelleştirdik.
        bottomNavigationBar: BottomNavigationBar(
          items: List.generate(iconList.length, (index) {
            // YENİ: Her bir menü elemanını animasyonlu bir indikatör ile oluşturuyoruz.
            return BottomNavigationBarItem(
              icon: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(iconList[index]),
                  SizedBox(height: 4.h),
                ],
              ),
              label: pageLabels[index],
            );
          }),
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          backgroundColor: Colors.grey.shade900.withOpacity(0.8),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.amber.shade400,
          unselectedItemColor: Colors.grey.shade600,
          selectedLabelStyle: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 12.sp),
          showSelectedLabels: true,
          showUnselectedLabels: true,
        ),
      ),
    );
  }
}