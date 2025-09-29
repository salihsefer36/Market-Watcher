import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';
import 'settings_page.dart';
import 'main.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<Map<String, dynamic>> _followedItems = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserAlarms();
  }

  Future<void> _fetchUserAlarms() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final userUid = _auth.currentUser?.uid;
      if (userUid == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final uri = Uri.parse("$backendBaseUrl/alerts?user_uid=$userUid");
      final res = await http.get(uri).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200 && mounted) {
        final List<dynamic> data = jsonDecode(res.body);
        setState(() {
          _followedItems = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      print("Error fetching alerts: $e");
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createOrEditAlarm(String market, String symbol, double percentage, {int? editId}) async {
    if (!mounted) return;
    final localizations = AppLocalizations.of(context)!;
    try {
      final userUid = _auth.currentUser?.uid;
      if (userUid == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.pleaseSignInFirst)));
        return;
      }
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.couldNotGetNotificationToken)));
        return;
      }

      final exists = _followedItems.any((alarm) {
        if (editId != null && alarm['id'] == editId) return false;
        String alarmSymbol = alarm['symbol'];
        String checkSymbol = symbol;
        if (alarm['market'] == 'CRYPTO') {
          if (alarmSymbol.endsWith("USDT")) alarmSymbol = alarmSymbol.substring(0, alarmSymbol.length - 4);
          if (checkSymbol.endsWith("USDT")) checkSymbol = checkSymbol.substring(0, checkSymbol.length - 4);
        }
        return alarm['market'] == market && alarmSymbol.toUpperCase() == checkSymbol.toUpperCase();
      });

      if (exists) {
        String displaySymbol = symbol;
        if (market == 'CRYPTO' && displaySymbol.endsWith('USDT')) {
          displaySymbol = displaySymbol.substring(0, displaySymbol.length - 1);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            backgroundColor: Colors.transparent,
            elevation: 0,
            content: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.redAccent.shade200, Colors.red.shade900]),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(localizations.alarmAlreadyExists(displaySymbol, market), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        );
        return;
      }

      final uri = editId != null ? Uri.parse("$backendBaseUrl/alerts/$editId") : Uri.parse("$backendBaseUrl/alerts");
      final body = jsonEncode({"market": market, "symbol": symbol, "percentage": percentage, "user_uid": userUid, "user_token": fcmToken});
      final res = editId != null
          ? await http.put(uri, headers: {"Content-Type": "application/json"}, body: body)
          : await http.post(uri, headers: {"Content-Type": "application/json"}, body: body);

      if (res.statusCode == 200) {
        await _fetchUserAlarms();
      } else {
        print("Error creating/editing alarm: ${res.body}");
      }
    } catch (e) {
      print("Create/Edit alarm error: $e");
    }
  }

  Future<void> _deleteAlarm(int id) async {
    try {
      final userUid = _auth.currentUser?.uid;
      if (userUid == null) return;
      final uri = Uri.parse("$backendBaseUrl/alerts/$id?user_uid=$userUid");
      final response = await http.delete(uri);
      if (response.statusCode != 200) {
        _fetchUserAlarms(); // If deletion fails on backend, refresh UI to show it again
      }
    } catch (e) {
      print("Delete alarm error: $e");
      _fetchUserAlarms();
    }
  }

  void _openSetAlarmDialog(BuildContext context, AppLocalizations localizations) {
    String? selectedMarket;
    String? selectedSymbol;
    double? selectedPercentage;
    final markets = ['BIST', 'NASDAQ', 'CRYPTO', 'METALS'];
    final percentages = [1, 2, 5, 10];
    List<String> symbolsForMarket = [];
    bool _isLoadingSymbols = false;

    Future<List<String>> fetchSymbolsForMarket(String market) async {
      try {
        final uri = Uri.parse("$backendBaseUrl/symbols_with_name?market=$market");
        final res = await http.get(uri);
        if (res.statusCode == 200) {
          final List<dynamic> data = jsonDecode(res.body);
          return data.map((e) => e['symbol'].toString()).toList();
        }
      } catch (e) {
        print("Error fetching symbols for $market: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.marketSymbolsCouldNotBeLoaded(market))));
        }
      }
      return [];
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(24.w),
          child: StatefulBuilder(
            builder: (builderContext, setState) {
              return SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.grey.shade900, Colors.black87]),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(color: Colors.amber.withOpacity(0.5)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(localizations.setAlarm, style: TextStyle(color: Colors.amber.shade400, fontSize: 24.sp, fontWeight: FontWeight.bold)),
                      SizedBox(height: 24.h),
                      _buildDropdownContainer(
                        icon: Icons.store_mall_directory_outlined,
                        child: DropdownButton<String>(
                          dropdownColor: Colors.grey.shade800,
                          isExpanded: true,
                          underline: const SizedBox(),
                          value: selectedMarket,
                          hint: Text(localizations.selectMarket, style: const TextStyle(color: Colors.grey)),
                          items: markets.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(color: Colors.white)))).toList(),
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() {
                              _isLoadingSymbols = true;
                              selectedMarket = value;
                              selectedSymbol = null;
                              symbolsForMarket = [];
                            });
                            final symbols = await fetchSymbolsForMarket(value);
                            setState(() {
                              symbolsForMarket = symbols;
                              _isLoadingSymbols = false;
                            });
                          },
                        ),
                      ),
                      SizedBox(height: 16.h),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 50.h,
                        child: _isLoadingSymbols
                            ? Center(child: CircularProgressIndicator(color: Colors.amber.shade600, strokeWidth: 2.5))
                            : (selectedMarket != null
                                ? _buildDropdownContainer(
                                    icon: Icons.analytics_outlined,
                                    child: DropdownButton<String>(
                                      dropdownColor: Colors.grey.shade800,
                                      isExpanded: true,
                                      underline: const SizedBox(),
                                      hint: Text(localizations.selectSymbol, style: const TextStyle(color: Colors.grey)),
                                      value: symbolsForMarket.contains(selectedSymbol) ? selectedSymbol : null,
                                      items: symbolsForMarket.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: Colors.white)))).toList(),
                                      onChanged: (value) => setState(() => selectedSymbol = value),
                                    ),
                                  )
                                : const SizedBox()),
                      ),
                      SizedBox(height: 16.h),
                      _buildDropdownContainer(
                        icon: Icons.percent_rounded,
                        child: DropdownButton<double>(
                          dropdownColor: Colors.grey.shade800,
                          isExpanded: true,
                          underline: const SizedBox(),
                          hint: Text(localizations.selectChangePercent, style: const TextStyle(color: Colors.grey)),
                          value: selectedPercentage,
                          items: percentages.map((p) => DropdownMenuItem(value: p.toDouble(), child: Text('$p%', style: const TextStyle(color: Colors.white)))).toList(),
                          onChanged: (value) => setState(() => selectedPercentage = value),
                        ),
                      ),
                      SizedBox(height: 24.h),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text(localizations.cancel, style: const TextStyle(color: Colors.grey)),
                          ),
                          SizedBox(width: 12.w),
                          ElevatedButton(
                            onPressed: (selectedMarket != null && selectedSymbol != null && selectedPercentage != null)
                                ? () async {
                                    String formattedSymbol = selectedSymbol!;
                                    if (selectedMarket == 'CRYPTO') {
                                      formattedSymbol = "${selectedSymbol!.toUpperCase()}T";
                                    }
                                    Navigator.pop(dialogContext); // Close dialog before async operation
                                    await _createOrEditAlarm(selectedMarket!, formattedSymbol, selectedPercentage!);
                                  }
                                : null,
                            child: Text(localizations.setAlarm),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _openEditAlarmDialog(BuildContext context, Map<String, dynamic> alert, AppLocalizations localizations) {
    String? selectedMarket = alert['market'];
    String? selectedSymbol = alert['symbol'];
    if (selectedMarket == 'CRYPTO' && selectedSymbol != null && selectedSymbol.endsWith('USDT')) {
      selectedSymbol = selectedSymbol.substring(0, selectedSymbol.length - 1);
    }
    
    double? selectedPercentage = alert['percentage']?.toDouble();

    final markets = ['BIST', 'NASDAQ', 'CRYPTO', 'METALS'];
    final percentages = [1, 2, 5, 10];
    List<String> symbolsForMarket = [];
    bool _isLoadingSymbols = false;

    Future<List<String>> _fetchSymbolsForMarket(String market) async {
      try {
        final uri = Uri.parse("$backendBaseUrl/symbols_with_name?market=$market");
        final res = await http.get(uri);
        if (res.statusCode == 200) {
          final List<dynamic> data = jsonDecode(res.body);
          return data.map((e) => e['symbol'].toString()).toList();
        }
      } catch (e) {
        print("Error fetching symbols for $market: $e");
      }
      return [];
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(24.w),
          child: StatefulBuilder(
            builder: (context, setState) {

              if (selectedMarket != null && symbolsForMarket.isEmpty && !_isLoadingSymbols) {
                setState(() => _isLoadingSymbols = true);
                _fetchSymbolsForMarket(selectedMarket!).then((symbols) {
                  setState(() {
                    symbolsForMarket = symbols;
                    _isLoadingSymbols = false;
                  });
                });
              }

              return SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.grey.shade900, Colors.black87],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(color: Colors.amber.withOpacity(0.5)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        localizations.editAlarm,
                        style: TextStyle(
                          color: Colors.amber.shade400,
                          fontSize: 24.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 24.h),
                      
                      _buildDropdownContainer(
                        icon: Icons.store_mall_directory_outlined,
                        child: DropdownButton<String>(
                          dropdownColor: Colors.grey.shade800,
                          isExpanded: true,
                          underline: const SizedBox(),
                          value: selectedMarket,
                          items: markets.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(color: Colors.white)))).toList(),
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() {
                              _isLoadingSymbols = true;
                              selectedMarket = value;
                              selectedSymbol = null;
                              symbolsForMarket = [];
                            });
                            final symbols = await _fetchSymbolsForMarket(value);
                            setState(() {
                              symbolsForMarket = symbols;
                              _isLoadingSymbols = false;
                            });
                          },
                        ),
                      ),
                      SizedBox(height: 16.h),
                      
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 50.h,
                        child: _isLoadingSymbols
                            ? Center(child: CircularProgressIndicator(color: Colors.amber.shade600, strokeWidth: 2.5))
                            : _buildDropdownContainer(
                                icon: Icons.analytics_outlined,
                                child: DropdownButton<String>(
                                  dropdownColor: Colors.grey.shade800,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  value: symbolsForMarket.contains(selectedSymbol) ? selectedSymbol : null,
                                  hint: Text(localizations.selectSymbol, style: TextStyle(color: Colors.grey)),
                                  items: symbolsForMarket.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: Colors.white)))).toList(),
                                  onChanged: (value) => setState(() => selectedSymbol = value),
                                ),
                              ),
                      ),
                      SizedBox(height: 16.h),
                      
                      _buildDropdownContainer(
                        icon: Icons.percent_rounded,
                        child: DropdownButton<double>(
                          dropdownColor: Colors.grey.shade800,
                          isExpanded: true,
                          underline: const SizedBox(),
                          value: selectedPercentage,
                          hint: Text(localizations.selectChangePercent, style: TextStyle(color: Colors.grey)),
                          items: percentages.map((p) => DropdownMenuItem(value: p.toDouble(), child: Text('$p%', style: const TextStyle(color: Colors.white)))).toList(),
                          onChanged: (value) => setState(() => selectedPercentage = value),
                        ),
                      ),
                      SizedBox(height: 24.h),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(localizations.cancel, style: TextStyle(color: Colors.grey)),
                          ),
                          SizedBox(width: 12.w),
                          ElevatedButton(
                            onPressed: () async {
                              if (selectedMarket != null && selectedSymbol != null && selectedPercentage != null) {
                                String formattedSymbol = selectedSymbol!;
                                if (selectedMarket == 'CRYPTO') {
                                  formattedSymbol = "${selectedSymbol!.toUpperCase()}T";
                                }
                                await _createOrEditAlarm(
                                  selectedMarket!,
                                  formattedSymbol,
                                  selectedPercentage!,
                                  editId: alert['id'],
                                );
                                Navigator.pop(context);
                              }
                            },
                            child: Text(localizations.save),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDropdownContainer({required IconData icon, required Widget child}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber.shade600, size: 20.sp),
          SizedBox(width: 12.w),
          Expanded(child: child),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black,
        title: Text(user?.displayName ?? localizations.marketWatcher, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22.sp)),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: Colors.amber, size: 30.sp),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage())),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
        child: Column(
          children: [
            Container(
              height: MediaQuery.of(context).size.height * 0.55,
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.grey.shade900.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(localizations.followedAlarms, style: TextStyle(color: Colors.amber.shade400, fontSize: 20.sp, fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.grey, height: 24),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator(color: Colors.amber))
                        : _followedItems.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.notifications_off_outlined, color: Colors.grey, size: 48.sp),
                                    SizedBox(height: 16.h),
                                    Text(localizations.noAlarmsYet, style: TextStyle(color: Colors.grey, fontSize: 16.sp)),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _fetchUserAlarms,
                                child: ListView.builder(
                                  itemCount: _followedItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _followedItems[index];
                                    String symbol = item['symbol'] ?? '';
                                    if (item['market'] == 'CRYPTO' && symbol.endsWith('USDT')) {
                                      symbol = symbol.substring(0, symbol.length - 1);
                                    }
                                    return Slidable(
                                      key: ValueKey(item['id']),
                                      endActionPane: ActionPane(
                                        motion: const DrawerMotion(),
                                        extentRatio: 0.25,
                                        children: [
                                          SlidableAction(
                                            onPressed: (context) {
                                              setState(() => _followedItems.removeAt(index));
                                              _deleteAlarm(item['id']);
                                            },
                                            backgroundColor: Colors.red.shade700,
                                            foregroundColor: Colors.white,
                                            icon: Icons.delete_forever,
                                            label: localizations.delete,
                                            borderRadius: BorderRadius.circular(12.r),
                                          ),
                                        ],
                                      ),
                                      child: ListTile(
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.amber.withOpacity(0.1),
                                          child: Icon(Icons.notifications_active_outlined, color: Colors.amber.shade400),
                                        ),
                                        title: Text(symbol, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.sp)),
                                        subtitle: Text(item['market'] ?? '', style: TextStyle(color: Colors.grey.shade400, fontSize: 12.sp)),
                                        trailing: Text('%${item['percentage']}', style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w500)),
                                        onTap: () => _openEditAlarmDialog(context, item, localizations),
                                      ),
                                    );
                                  },
                                ),
                              ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24.h),
            SizedBox(
              width: double.infinity,
              height: 55.h,
              child: ElevatedButton.icon(
                icon: Icon(Icons.add_alert_rounded, size: 28.sp),
                label: Text(localizations.setAlarm, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r))),
                onPressed: () => _openSetAlarmDialog(context, localizations),
              ),
            ),
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              height: 55.h,
              child: ElevatedButton.icon(
                icon: Icon(Icons.bar_chart_rounded, size: 28.sp),
                label: Text(localizations.watchMarkets, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.amber, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r))),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchMarketPage())),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- WATCH MARKET PAGE ---
class WatchMarketPage extends StatefulWidget {
  const WatchMarketPage({super.key});
  @override
  State<WatchMarketPage> createState() => _WatchMarketPageState();
}
class _WatchMarketPageState extends State<WatchMarketPage> with SingleTickerProviderStateMixin {
  Map<String, List<Map<String, dynamic>>> marketData = {"BIST": [], "NASDAQ": [], "CRYPTO": [], "METALS": []};
  bool loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: marketData.keys.length, vsync: this);
    fetchAllDataEfficiently();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> fetchAllDataEfficiently() async {
    if (!mounted) return;
    final localizations = AppLocalizations.of(context)!;
    setState(() => loading = true);
    marketData.forEach((key, value) => value.clear());
    try {
      final res = await http.get(Uri.parse("$backendBaseUrl/prices")).timeout(const Duration(seconds: 60));
      if (res.statusCode == 200) {
        final List<dynamic> allData = jsonDecode(res.body);
        for (var item in allData) {
          final market = item['market'];
          if (market != null && marketData.containsKey(market)) {
            marketData[market]?.add(item);
          }
        }
      } else {
        throw Exception('Failed to load market data');
      }
    } catch (e) {
      print("Error fetching market data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.noMarketDataFound)));
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.amber),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(localizations.watchMarketChart, style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 22.sp)),
        backgroundColor: Colors.black,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.grey,
          labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp),
          tabs: marketData.keys.map((market) {
            String tabText = market;
            if (market == "CRYPTO") tabText = localizations.crypto;
            if (market == "METALS") tabText = localizations.metals;
            return Tab(text: tabText);
          }).toList(),
        ),
      ),
      backgroundColor: Colors.black,
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : TabBarView(
              controller: _tabController,
              children: marketData.keys.map((market) {
                final data = marketData[market] ?? [];
                final filteredData = data.where((item) => item['price'] != null && item['price'] > 0).toList();
                return _buildMarketList(market, filteredData);
              }).toList(),
            ),
    );
  }

  Widget _buildMarketList(String market, List<Map<String, dynamic>> data) {
    final localizations = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text(localizations.symbol, style: TextStyle(color: Colors.grey, fontSize: 12.sp))),
              Expanded(flex: 5, child: Text(localizations.name, style: TextStyle(color: Colors.grey, fontSize: 12.sp))),
              Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: Text(localizations.price, style: TextStyle(color: Colors.grey, fontSize: 12.sp)))),
            ],
          ),
        ),
        const Divider(color: Color(0xFF222222), height: 1),
        Expanded(
          child: data.isEmpty
              ? Center(child: Text(localizations.noDataFound, style: TextStyle(color: Colors.grey, fontSize: 16.sp)))
              : RefreshIndicator(
                  onRefresh: fetchAllDataEfficiently,
                  child: ListView.separated(
                    itemCount: data.length,
                    separatorBuilder: (context, index) => const Divider(color: Color(0xFF222222), height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      final item = data[index];
                      final priceValue = item['price'] as num;
                      String currencySymbol = (market == "BIST" || market == "METALS") ? "₺" : "\$";
                      String displayPrice = "${priceValue.toStringAsFixed(2)}$currencySymbol";
                      String displayName = item['name'] ?? item['symbol'] ?? '';
                      if (market == "METALS") displayName = "Gram $displayName";
                      String displaySymbol = item['symbol'] ?? '';
                      if (market == "CRYPTO" && displaySymbol.endsWith('USDT')) {
                        displaySymbol = displaySymbol.substring(0, displaySymbol.length - 1);
                      }
                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                        child: Row(
                          children: [
                            Expanded(flex: 3, child: Text(displaySymbol, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp))),
                            Expanded(flex: 5, child: Text(displayName, style: TextStyle(color: Colors.grey.shade400, fontSize: 13.sp), overflow: TextOverflow.ellipsis)),
                            Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: Text(displayPrice, style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14.sp, letterSpacing: 0.5)))),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}