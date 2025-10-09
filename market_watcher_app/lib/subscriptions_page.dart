import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  bool _isLoading = true;
  bool _isPurchasing = false;
  Offerings? _offerings;
  String _currentPlanIdentifier = 'free';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchSubscriptionData();
    });
  }

  Future<void> _fetchSubscriptionData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final offerings = await Purchases.getOfferings();
      final customerInfo = await Purchases.getCustomerInfo();
      
      final entitlements = customerInfo.entitlements.active.keys;
      if (entitlements.contains('ultra_access')) {
        _currentPlanIdentifier = 'ultra';
      } else if (entitlements.contains('pro_access')) {
        _currentPlanIdentifier = 'pro';
      } else {
        _currentPlanIdentifier = 'free';
      }

      if (mounted) {
        setState(() {
          _offerings = offerings;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("RevenueCat verileri çekilirken hata: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _purchasePackage(Package packageToPurchase) async {
    if (_isPurchasing) return;
    setState(() => _isPurchasing = true);
    
    try {
      CustomerInfo customerInfo = await Purchases.purchasePackage(packageToPurchase);
      final entitlements = customerInfo.entitlements.active.keys;
      
      // RevenueCat'in "Offerings" sistemi, offeringIdentifier'ı "pro_monthly" yerine "pro" olarak tutabilir.
      // Bu yüzden entitlement anahtarıyla (örn: "pro_access") karşılaştırmak daha güvenilirdir.
      if (entitlements.isNotEmpty) {
         print("Satın alma başarılı!");
         await _fetchSubscriptionData();
      }
    } catch (e) {
      print("Satın alma sırasında hata: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.anErrorOccurred))
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    
    final monthlyProPackage = _offerings?.current?.getPackage('pro_monthly');
    final monthlyUltraPackage = _offerings?.current?.getPackage('ultra_monthly');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.amber))
              : ListView(
                  padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 16.w),
                  children: [
                    _buildPlanCard(
                      localizations: localizations,
                      icon: Icons.shield_outlined,
                      title: 'Free',
                      price: localizations.free,
                      features: [
                        localizations.featureCheck10Min,
                        localizations.feature5Alarms,
                      ],
                      isHighlighted: false,
                      buttonText: _currentPlanIdentifier == 'free' ? localizations.currentPlan : localizations.downgrade,
                      onPressed: _currentPlanIdentifier == 'free' ? null : () { /* Downgrade logic */ },
                    ),
                    _buildPlanCard(
                      localizations: localizations,
                      icon: Icons.rocket_launch_outlined,
                      title: 'Pro',
                      price: monthlyProPackage?.storeProduct.priceString ?? '\$2.99/mo',
                      features: [
                        localizations.featureCheck3Min,
                        localizations.feature20Alarms,
                        localizations.featureNoAds,
                      ],
                      isHighlighted: true,
                      buttonText: _currentPlanIdentifier == 'pro' ? localizations.currentPlan : localizations.upgrade,
                      onPressed: _currentPlanIdentifier == 'pro' || monthlyProPackage == null ? null : () => _purchasePackage(monthlyProPackage),
                    ),
                    _buildPlanCard(
                      localizations: localizations,
                      icon: Icons.diamond_outlined,
                      title: 'Ultra',
                      price: monthlyUltraPackage?.storeProduct.priceString ?? '\$9.99/mo',
                      features: [
                        localizations.featureCheck1Min,
                        localizations.featureUnlimitedAlarms,
                        localizations.featurePrioritySupport,
                        localizations.featureNoAds,
                      ],
                      isHighlighted: false,
                      buttonText: _currentPlanIdentifier == 'ultra' ? localizations.currentPlan : localizations.upgrade,
                      onPressed: _currentPlanIdentifier == 'ultra' || monthlyUltraPackage == null ? null : () => _purchasePackage(monthlyUltraPackage),
                    ),
                  ].animate(interval: 200.ms).fadeIn(duration: 500.ms).slideY(begin: 0.3, curve: Curves.easeOutCubic),
                ),
          
          if (_isPurchasing)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: const Center(child: CircularProgressIndicator(color: Colors.amber)),
            ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required AppLocalizations localizations,
    required IconData icon,
    required String title,
    required String price,
    required List<String> features,
    required bool isHighlighted,
    required String buttonText,
    required VoidCallback? onPressed,
  }) {
    bool isUltra = title.toLowerCase() == 'ultra';
    
    // Renk tanımlamaları
    final Gradient cardGradient = isHighlighted
        ? LinearGradient(colors: [Colors.amber.shade700, Colors.orange.shade800], begin: Alignment.topLeft, end: Alignment.bottomRight)
        : isUltra
            ? LinearGradient(colors: [Colors.deepPurple.shade700, Colors.indigo.shade900], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : LinearGradient(colors: [Colors.grey.shade900, const Color(0xFF2C2C2E)]);
            
    final Color borderColor = isHighlighted
        ? Colors.amber.shade300.withOpacity(0.8)
        : isUltra
            ? Colors.purple.shade200
            : Colors.grey.shade700;
            
    final Color iconColor = isHighlighted
        ? Colors.white
        : isUltra
            ? Colors.purple.shade200
            : Colors.amber.shade400;

    final BoxShadow boxShadow = BoxShadow(
      color: isHighlighted
          ? Colors.amber.shade900.withOpacity(0.4)
          : isUltra
              ? Colors.purple.shade900.withOpacity(0.6)
              : Colors.black.withOpacity(0.5),
      blurRadius: 15,
      spreadRadius: 1,
      offset: const Offset(0, 8),
    );

    return Container(
      margin: EdgeInsets.only(bottom: 24.h),
      decoration: BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [boxShadow],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.all(20.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, color: iconColor, size: 28.sp),
                    SizedBox(width: 12.w),
                    Text(title, style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold, color: Colors.white)),
                    const Spacer(),
                    Text(price, style: TextStyle(fontSize: 18.sp, color: Colors.white, fontWeight: FontWeight.w500)),
                  ],
                ),
                const Divider(color: Colors.white24, height: 30),
                ...features.map((feature) => _buildFeatureRow(feature, isHighlighted || isUltra)).toList(),
                SizedBox(height: 20.h),
                ElevatedButton(
                  onPressed: onPressed,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    backgroundColor: isHighlighted ? Colors.white : (isUltra ? Colors.purple.shade300 : Colors.amber.shade600),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                    disabledBackgroundColor: Colors.grey.shade700,
                    textStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                  ),
                  child: Text(buttonText),
                ),
              ],
            ),
          ),
          if (isHighlighted)
            Positioned(
              top: -15,
              left: 20.w,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 4.h, horizontal: 12.w),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Text(
                  localizations.bestOffer,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.amber.shade400, fontWeight: FontWeight.bold, fontSize: 12.sp),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(String feature, bool isHighlighted) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.check, color: isHighlighted ? Colors.white : Colors.amber.shade400, size: 20.sp),
          SizedBox(width: 12.w),
          Expanded(child: Text(feature, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14.sp))),
        ],
      ),
    );
  }
}