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

  // Sayfaların listesi
  static const List<Widget> _widgetOptions = <Widget>[
    AlarmsPage(), // Eski HomePage
    WatchMarketPage(),
    SubscriptionsPage(), // Yeni Sayfa
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
    final pageTitles = [
      localizations.followedAlarms,
      localizations.watchMarkets,
      localizations.subscriptions, // Yerelleştirme dosyanıza eklemeniz gerekebilir
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
          title: Text(
            pageTitles[_selectedIndex],
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22.sp,
            ),
          ),
          // Sadece Alarmlar sayfasındayken "+" butonunu göster
          actions: _selectedIndex == 0
              ? [
                  // AlarmsPage'in içindeki butonu buraya taşıdık
                  (context.findAncestorWidgetOfExactType<AlarmsPage>()?.createState() as AlarmsPageState?)
                          ?.buildSetAlarmButton(context) ??
                      const SizedBox.shrink(),
                ]
              : null,
        ),
        body: Center(
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: const Icon(Icons.notifications_active_outlined),
              label: localizations.alarms, // Yerelleştirme dosyanıza ekleyin
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.bar_chart_rounded),
              label: localizations.markets, // Yerelleştirme dosyanıza ekleyin
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