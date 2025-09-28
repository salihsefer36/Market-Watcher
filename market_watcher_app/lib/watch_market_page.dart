import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';

class WatchMarketPage extends StatefulWidget {
  const WatchMarketPage({super.key});
  @override
  State<WatchMarketPage> createState() => _WatchMarketPageState();
}

class _WatchMarketPageState extends State<WatchMarketPage> with SingleTickerProviderStateMixin {

  
  Map<String, List<Map<String, dynamic>>> marketData = {
    "BIST": [],
    "NASDAQ": [],
    "CRYPTO": [],
    "METALS": [],
  };
  bool loading = true;

  // 2. TabController is defined for managing tabs.
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // The controller is initialized with a length matching the number of markets.
    _tabController = TabController(length: marketData.keys.length, vsync: this);
    fetchAllDataEfficiently(); // Switched to a more efficient data fetching method
  }

  @override
  void dispose() {
    _tabController.dispose(); // Clean up the controller when the page is closed
    super.dispose();
  }
  
  // --- A MORE EFFICIENT DATA FETCHING METHOD ---
  Future<void> fetchAllDataEfficiently() async {
    final localizations = AppLocalizations.of(context)!;
    if (!mounted) return;
    setState(() => loading = true);
    
    // Clear previous data
    marketData.forEach((key, value) => value.clear());

    try {
      // Fetch all prices and symbols in a single API call
      final res = await http.get(Uri.parse("$backendBaseUrl/prices"));
      if (res.statusCode == 200) {
        final List<dynamic> allData = jsonDecode(res.body);
        
        // Sort the data from the single endpoint into the correct market lists
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.noDataFound),
          ),
        );
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
        title: Text(
          localizations.watchMarketChart,
          style: TextStyle(
            color: Colors.amber,
            fontWeight: FontWeight.bold,
            fontSize: 22.sp,
          ),
        ),
        backgroundColor: Colors.black,
        // 3. A TabBar is added to the bottom of the AppBar.
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.grey,
          labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp),
          tabs: marketData.keys.map((market) => Tab(text: market)).toList(),
        ),
      ),
      backgroundColor: Colors.black,
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          // 4. The body is now a TabBarView, which displays content based on the selected tab.
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

  // 5. This new helper method builds the content for each tab.
  Widget _buildMarketList(String market, List<Map<String, dynamic>> data) {
    final localizations = AppLocalizations.of(context)!;
    return Column(
      children: [
        // Column Headers
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
        
        // The List
        Expanded(
          child: data.isEmpty
              ? Center(child: Text(localizations.noData, style: TextStyle(color: Colors.grey, fontSize: 16.sp)))
              : RefreshIndicator(
                  onRefresh: fetchAllDataEfficiently,
                  color: Colors.amber,
                  backgroundColor: Colors.grey.shade900,
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

                      // Clean crypto symbols for display
                      String displaySymbol = item['symbol'] ?? '';
                      if (market == "CRYPTO" && displaySymbol.endsWith('USDT')) {
                        displaySymbol = displaySymbol.substring(0, displaySymbol.length - 4);
                      }

                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(displaySymbol, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp)),
                            ),
                            Expanded(
                              flex: 5,
                              child: Text(displayName, style: TextStyle(color: Colors.grey.shade400, fontSize: 13.sp), overflow: TextOverflow.ellipsis),
                            ),
                            Expanded(
                              flex: 3,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(displayPrice, style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14.sp, letterSpacing: 0.5)),
                              ),
                            ),
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