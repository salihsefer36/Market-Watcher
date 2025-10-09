import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_animate/flutter_animate.dart';

class WatchMarketPage extends StatefulWidget {
  const WatchMarketPage({super.key});
  @override
  State<WatchMarketPage> createState() => _WatchMarketPageState();
}

class _WatchMarketPageState extends State<WatchMarketPage> with SingleTickerProviderStateMixin {
  Map<String, List<Map<String, dynamic>>> marketData = {
    "BIST": [], "NASDAQ": [], "CRYPTO": [], "METALS": [],
  };
  bool loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: marketData.keys.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {}); // Sekme değiştiğinde animasyonların tekrar oynaması için
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        fetchAllDataEfficiently();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> fetchAllDataEfficiently() async {
    if (!mounted) return;

    final localizations = AppLocalizations.of(context)!;
    final userUid = FirebaseAuth.instance.currentUser?.uid;
    
    if (userUid == null) {
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.pleaseSignInFirst)));
            setState(() => loading = false);
        }
        return; 
    }
    
    String apiUrl = "$backendBaseUrl/prices?user_uid=$userUid";
    
    if (!loading) { 
      setState(() => loading = true);
    }

    // marketData'yı temizlemek yerine yeni bir map oluşturuyoruz
    final initialMarketData = { for (var key in marketData.keys) key : <Map<String, dynamic>>[] };

    try {
      final res = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 15));
      
      if (res.statusCode == 200) {
        if (!mounted) return;
        final List<dynamic> allData = jsonDecode(res.body);

        for (var item in allData) {
          final market = item['market'];
          if (market != null && initialMarketData.containsKey(market)) {
            initialMarketData[market]?.add(item);
          }
        }
        
        if (mounted) {
          setState(() {
            marketData = initialMarketData;
            loading = false; 
          });
        }
      } else {
        throw Exception('Failed to load market data with status code: ${res.statusCode}');
      }
    } catch (e) {
      print("Error fetching market data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.noMarketDataFound)));
        setState(() => loading = false);
      }
    }
  }

  IconData _getIconForMarket(String market) {
    switch (market) {
      case "BIST":
      case "NASDAQ":
        return Icons.business_center_outlined;
      case "CRYPTO":
        return Icons.currency_bitcoin_rounded;
      case "METALS":
        return Icons.ssid_chart_rounded;
      default:
        return Icons.show_chart_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.amber.shade400,
          indicatorWeight: 3.0,
          labelColor: Colors.amber.shade400,
          unselectedLabelColor: Colors.grey.shade500,
          labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: 14.sp),
          tabs: marketData.keys.map((market) {
            String tabText = market;
            if (market == "CRYPTO") tabText = localizations.crypto;
            if (market == "METALS") tabText = localizations.metals;
            return Tab(text: tabText);
          }).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: marketData.keys.map((market) {
              final data = marketData[market] ?? [];
              final filteredData = data.where((item) => item['price'] != null && item['price'] > 0).toList();
              return _buildMarketList(market, filteredData);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMarketList(String market, List<Map<String, dynamic>> data) {
    final localizations = AppLocalizations.of(context)!;

    if (loading) {
      return _buildShimmerList();
    }

    if (data.isEmpty) {
      return Center(child: Text(localizations.noDataFound, style: TextStyle(color: Colors.grey.shade500, fontSize: 16.sp)));
    }

    return RefreshIndicator(
      onRefresh: fetchAllDataEfficiently,
      color: Colors.amber.shade400,
      backgroundColor: Colors.grey.shade900,
      child: ListView.builder(
        padding: EdgeInsets.all(12.w),
        itemCount: data.length,
        itemBuilder: (context, index) {
          final item = data[index];
          final priceValue = item['price'] as num;

          String currencySymbol;
          final localeCode = Localizations.localeOf(context).languageCode;
          
          if (market == "BIST") {
            currencySymbol = "₺";
          } else if (market == "METALS") {
            switch (localeCode.toLowerCase()) {
              case 'tr': currencySymbol = '₺'; break;
              case 'de':
              case 'fr':
              case 'it':
              case 'es': currencySymbol = '€'; break;
              case 'ru': currencySymbol = '₽'; break;
              case 'ja': currencySymbol = '¥'; break;
              case 'zh': currencySymbol = '¥'; break;
              case 'hi': currencySymbol = '₹'; break;
              case 'ar': currencySymbol = '﷼'; break;
              default: currencySymbol = '\$'; break;
            }
          } else {
            currencySymbol = "\$";
          }
          
          String displayPrice = "${priceValue.toStringAsFixed(2)}$currencySymbol";
          String displayName;
          final String? itemSymbol = item['symbol']?.toString();
          final String? itemName = item['name']?.toString();

          if (market == "METALS") {
            final metalName = itemSymbol ?? '';
            String localizedMetalName = metalName;
            
            if (metalName == "ALTIN") {
              localizedMetalName = AppLocalizations.of(context)!.metalGold;
            } else if (metalName == "GÜMÜŞ") {
              localizedMetalName = AppLocalizations.of(context)!.metalSilver;
            } else if (metalName == "BAKIR") {
              localizedMetalName = AppLocalizations.of(context)!.metalCopper;
            }
            displayName = "${AppLocalizations.of(context)!.gram} $localizedMetalName";
          } else {
            displayName = itemName ?? itemSymbol ?? '';
          }

          String displaySymbol = itemSymbol ?? '';
          if (market == "CRYPTO" && displaySymbol.endsWith('USDT')) {
            displaySymbol = displaySymbol.substring(0, displaySymbol.length - 4);
          } else if (market == "METALS") {
            if (displaySymbol == "ALTIN") {
              displaySymbol = AppLocalizations.of(context)!.metalGold;
            } else if (displaySymbol == "GÜMÜŞ") {
              displaySymbol = AppLocalizations.of(context)!.metalSilver;
            } else if (displaySymbol == "BAKIR") {
              displaySymbol = AppLocalizations.of(context)!.metalCopper;
            }
          }

          return Container(
            margin: EdgeInsets.only(bottom: 12.h),
            decoration: BoxDecoration(
              color: Colors.grey.shade900.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black.withOpacity(0.3),
                    child: Icon(_getIconForMarket(market), color: Colors.amber.shade400, size: 22.sp),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displaySymbol,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.sp),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          displayName,
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 13.sp),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    displayPrice,
                    style: TextStyle(
                      color: Colors.amber.shade300,
                      fontWeight: FontWeight.bold,
                      fontSize: 16.sp,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          )
          .animate()
          .fadeIn(duration: 250.ms, delay: (10 * index).ms, curve: Curves.easeOutCubic)
          .slideX(begin: 0.1, duration: 250.ms, delay: (10 * index).ms, curve: Curves.easeOutCubic);
        },
      ),
    );
  }

  Widget _buildShimmerList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade900,
      highlightColor: Colors.grey.shade800,
      child: ListView.builder(
        padding: EdgeInsets.all(12.w),
        itemCount: 10,
        itemBuilder: (context, index) {
          return Container(
            margin: EdgeInsets.only(bottom: 12.h),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Row(
              children: [
                const CircleAvatar(backgroundColor: Colors.black),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 80.w, height: 16.h, color: Colors.black),
                      SizedBox(height: 8.h),
                      Container(width: 150.w, height: 12.h, color: Colors.black),
                    ],
                  ),
                ),
                Container(width: 100.w, height: 16.h, color: Colors.black),
              ],
            ),
          );
        },
      ),
    );
  }
}