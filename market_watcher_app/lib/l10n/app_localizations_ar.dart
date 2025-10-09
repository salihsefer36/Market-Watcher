// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get marketWatcher => 'مراقب السوق';

  @override
  String get instantMarketAlarms => 'تنبيهات فورية للسوق';

  @override
  String get continueWithGoogle => 'المتابعة باستخدام جوجل';

  @override
  String get followedAlarms => 'التنبيهات المتبعة';

  @override
  String get noAlarmsYet => 'لم يتم تعيين أي تنبيهات بعد.';

  @override
  String get setAlarm => 'ضبط';

  @override
  String get watchMarkets => 'مراقبة الأسواق';

  @override
  String get settings => 'الإعدادات';

  @override
  String get general => 'عام';

  @override
  String get applicationLanguage => 'لغة التطبيق';

  @override
  String get notifications => 'الإشعارات';

  @override
  String get forAllAlarms => 'لجميع التنبيهات';

  @override
  String get account => 'الحساب';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get language => 'العربية';

  @override
  String get selectLanguage => 'اختر اللغة';

  @override
  String get cancel => 'إلغاء';

  @override
  String get delete => 'حذف';

  @override
  String get edit => 'تعديل';

  @override
  String get save => 'حفظ';

  @override
  String get symbol => 'الرمز';

  @override
  String get name => 'الاسم';

  @override
  String get price => 'السعر';

  @override
  String get noDataFound => 'لا توجد بيانات';

  @override
  String get theAlarmHasNotBeenSetYet => 'لم يتم تعيين التنبيه بعد.';

  @override
  String get selectMarket => 'اختر السوق';

  @override
  String get selectSymbol => 'اختر الرمز';

  @override
  String get selectChangePercent => 'اختر نسبة التغيير %';

  @override
  String get editAlarm => 'تعديل التنبيه';

  @override
  String get watchMarket => 'مراقبة السوق';

  @override
  String get signInWithGoogle => 'تسجيل الدخول باستخدام جوجل';

  @override
  String get crypto => 'عملات مشفرة';

  @override
  String get metals => 'معادن';

  @override
  String get noData => 'لا توجد بيانات';

  @override
  String get pleaseSignInFirst => 'يرجى تسجيل الدخول أولاً';

  @override
  String get couldNotGetNotificationToken =>
      'لا يمكن الحصول على رمز الإشعار. يرجى المحاولة مرة أخرى.';

  @override
  String alarmAlreadyExists(Object displaySymbol, Object market) {
    return 'التنبيه موجود بالفعل لـ $displaySymbol في $market';
  }

  @override
  String marketSymbolsCouldNotBeLoaded(Object market) {
    return 'لا يمكن تحميل رموز $market.';
  }

  @override
  String get noMarketDataFound => 'لم يتم العثور على بيانات للسوق';

  @override
  String get watchMarketChart => 'مراقبة السوق 📈';

  @override
  String get gram => 'جرام';

  @override
  String get metalGold => 'ذهب';

  @override
  String get metalSilver => 'فضة';

  @override
  String get metalCopper => 'نحاس';

  @override
  String get subscriptionPlans => 'خطط الاشتراك';

  @override
  String get alarms => 'التنبيهات';

  @override
  String get markets => 'الأسواق';

  @override
  String get subscriptions => 'الاشتراكات';
}
