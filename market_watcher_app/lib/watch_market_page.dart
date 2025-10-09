import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
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
    "BIST": [], "NASDAQ": [], "CRYPTO": [], "METALS": [],
  };
  bool loading = true;
  late TabController _tabController;

   @override
  void initState() {
    super.initState();
    _tabController = TabController(length: marketData.keys.length, vsync: this);
    // ÖNEMLİ: Bu fetchAllDataEfficiently çağrısını buraya taşıyoruz
    // Bu sayede sayfa her açıldığında verileri yeniler.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fetchAllDataEfficiently();
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

    marketData.forEach((key, value) => value.clear());

    try {
      final res = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 10));
      
      if (res.statusCode == 200) {
        if (!mounted) return;
        final List<dynamic> allData = jsonDecode(res.body);
        final newMarketData = Map<String, List<Map<String, dynamic>>>.from(marketData);

        for (var item in allData) {
          final market = item['market'];
          if (market != null && newMarketData.containsKey(market)) {
            newMarketData[market]?.add(item);
          }
        }
        
        if (mounted) {
          setState(() {
            marketData = newMarketData;
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

@override
  Widget build(BuildContext context) {
    // Bu sayfanın kendi Scaffold ve AppBar'ı yok.
    // Direkt olarak TabBar ve TabBarView'ı içeren bir Column döndürüyoruz.
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.amber.shade400,
          labelColor: Colors.amber.shade400,
          unselectedLabelColor: Colors.grey.shade500,
          labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp),
          tabs: marketData.keys.map((market) {
            String tabText = market;
            // ... tabText yerelleştirme kodunuz aynı ...
            return Tab(text: tabText);
          }).toList(),
        ),
        Expanded(
          child: loading
              ? Center(child: CircularProgressIndicator(color: Colors.amber.shade400))
              : TabBarView(
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
    return Column(
      children: [
        // Başlıklar: Daha net bir çizgi ve font
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF333333), width: 1.0)),
          ),
          child: Row(
            children: [
              Expanded(flex: 6, child: Text(localizations.symbol, style: TextStyle(color: Colors.grey.shade400, fontSize: 12.sp, fontWeight: FontWeight.bold))),
              Expanded(flex: 10, child: Text(localizations.name, style: TextStyle(color: Colors.grey.shade400, fontSize: 12.sp, fontWeight: FontWeight.bold))),
              Expanded(flex: 7, child: Align(alignment: Alignment.centerRight, child: Text(localizations.price, style: TextStyle(color: Colors.grey.shade400, fontSize: 12.sp, fontWeight: FontWeight.bold)))),
            ],
          ),
        ),
        Expanded(
          child: data.isEmpty
              ? Center(child: Text(localizations.noDataFound, style: TextStyle(color: Colors.grey.shade500, fontSize: 16.sp)))
              : RefreshIndicator(
                  onRefresh: fetchAllDataEfficiently,
                  color: Colors.amber.shade400,
                  child: ListView.separated(
                    itemCount: data.length,
                    separatorBuilder: (context, index) => const Divider(color: Color(0xFF333333), height: 1), // Daha belirgin ayırıcı
                    itemBuilder: (context, index) {
                      final item = data[index];
                      final priceValue = item['price'] as num;
                      
                      String currencySymbol;
                      
                      // 1. Dili al
                      final localeCode = Localizations.localeOf(context).languageCode;
                      
                      if (market == "BIST") {
                        currencySymbol = "₺"; 
                      } else if (market == "METALS") {
                        switch (localeCode.toLowerCase()) {
                            case 'tr': currencySymbol = '₺'; break;
                            case 'de':
                            case 'fr':
                            case 'it':
                            case 'es': currencySymbol = '€'; break; // Euro for European languages
                            case 'ru': currencySymbol = '₽'; break; // Russian Ruble
                            case 'ja': currencySymbol = '¥'; break; // Japanese Yen
                            case 'zh': currencySymbol = '¥'; break; // Chinese Yuan
                            case 'hi': currencySymbol = '₹'; break; // Indian Rupi
                            case 'ar': currencySymbol = '﷼'; break; // Riyal (Arabic)
                            default: currencySymbol = '\$'; break; // For others USD
                        }
                      } else {
                        // NASDAQ and CRYPTO USD
                        currencySymbol = "\$"; 
                      }
                      
                      String displayPrice = "${priceValue.toStringAsFixed(2)}$currencySymbol";
                      String displayName;
                      
                      // Metadata (market, name, symbol) alınırken null kontrolü
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
                      }else {
                          displayName = itemName ?? itemSymbol ?? '';
                      }

                      String displaySymbol = itemSymbol ?? '';
                      if (market == "CRYPTO" && displaySymbol.endsWith('USDT')) {
                        displaySymbol = displaySymbol.substring(0, displaySymbol.length - 4); // Cut 4 character (USDT)
                      }else if (market == "METALS") {
                          // Metal sembollerini de localize etme
                          if (displaySymbol == "ALTIN") {
                              displaySymbol = AppLocalizations.of(context)!.metalGold;
                          } else if (displaySymbol == "GÜMÜŞ") {
                              displaySymbol = AppLocalizations.of(context)!.metalSilver;
                          } else if (displaySymbol == "BAKIR") {
                              displaySymbol = AppLocalizations.of(context)!.metalCopper;
                          }
                      }

                      // Liste elemanına hafif arka plan rengi ve hover efekti ekleme
                      return Container(
                        color: index.isEven ? Colors.black.withOpacity(0.1) : Colors.transparent,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 6, 
                                child: Text(
                                  displaySymbol, 
                                  style: TextStyle(
                                    color: Colors.white, 
                                    fontWeight: FontWeight.w600, // Daha belirgin
                                    fontSize: 14.sp
                                  )
                                )
                              ),
                              Expanded(
                                flex: 10, 
                                child: Text(
                                  displayName, 
                                  style: TextStyle(
                                    color: Colors.grey.shade400, 
                                    fontSize: 13.sp
                                  ), 
                                  overflow: TextOverflow.ellipsis
                                )
                              ),
                              Expanded(
                                flex: 7, 
                                child: Align(
                                  alignment: Alignment.centerRight, 
                                  child: Text(
                                    displayPrice, 
                                    style: TextStyle(
                                      color: Colors.amber.shade300, 
                                      fontWeight: FontWeight.bold, 
                                      fontSize: 14.sp, 
                                      letterSpacing: 0.5
                                    )
                                  )
                                )
                              ),
                            ],
                          ),
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