import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';

class SubscriptionsPage extends StatelessWidget {
  const SubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    
    // Bu sayfa, RevenueCat entegrasyonu yapıldığında doldurulacak.
    // Şimdilik basit bir yer tutucu.
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.workspace_premium_outlined,
            size: 60.sp,
            color: Colors.grey.shade700,
          ),
          SizedBox(height: 20.h),
          Text(
            localizations.subscriptionPlans, // Yerelleştirme dosyanıza ekleyin
            style: TextStyle(
              fontSize: 18.sp,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}