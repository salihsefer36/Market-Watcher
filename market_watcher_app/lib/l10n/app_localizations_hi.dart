// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get marketWatcher => 'मार्केट वॉचर';

  @override
  String get instantMarketAlarms => 'तुरंत बाजार अलार्म';

  @override
  String get continueWithGoogle => 'Google से जारी रखें';

  @override
  String get followedAlarms => 'अनुसरण किए गए अलार्म';

  @override
  String get noAlarmsYet => 'अभी तक कोई अलार्म सेट नहीं किया गया है।';

  @override
  String get setAlarm => 'सेट करें';

  @override
  String get watchMarkets => 'बाजार देखें';

  @override
  String get settings => 'सेटिंग्स';

  @override
  String get general => 'सामान्य';

  @override
  String get applicationLanguage => 'एप्लिकेशन भाषा';

  @override
  String get notifications => 'सूचनाएँ';

  @override
  String get forAllAlarms => 'सभी अलार्म के लिए';

  @override
  String get account => 'खाता';

  @override
  String get signOut => 'साइन आउट';

  @override
  String get language => 'हिन्दी';

  @override
  String get selectLanguage => 'भाषा चुनें';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get delete => 'हटाएँ';

  @override
  String get edit => 'संपादित करें';

  @override
  String get save => 'सहेजें';

  @override
  String get symbol => 'प्रतीक';

  @override
  String get name => 'नाम';

  @override
  String get price => 'मूल्य';

  @override
  String get noDataFound => 'कोई डेटा नहीं मिला';

  @override
  String get theAlarmHasNotBeenSetYet => 'अलार्म अभी तक सेट नहीं किया गया है।';

  @override
  String get selectMarket => 'बाजार चुनें';

  @override
  String get selectSymbol => 'प्रतीक चुनें';

  @override
  String get selectChangePercent => 'बदलाव % चुनें';

  @override
  String get editAlarm => 'अलार्म संपादित करें';

  @override
  String get watchMarket => 'बाजार देखें';

  @override
  String get signInWithGoogle => 'Google से साइन इन करें';

  @override
  String get crypto => 'क्रिप्टो';

  @override
  String get metals => 'धातुएँ';

  @override
  String get noData => 'कोई डेटा नहीं';

  @override
  String get pleaseSignInFirst => 'कृपया पहले साइन इन करें';

  @override
  String get couldNotGetNotificationToken =>
      'सूचना टोकन प्राप्त नहीं हो सका। कृपया पुनः प्रयास करें।';

  @override
  String alarmAlreadyExists(Object displaySymbol, Object market) {
    return '$market में $displaySymbol के लिए अलार्म पहले से मौजूद है';
  }

  @override
  String marketSymbolsCouldNotBeLoaded(Object market) {
    return '$market प्रतीक लोड नहीं किए जा सके।';
  }

  @override
  String get noMarketDataFound => 'कोई बाजार डेटा नहीं मिला';

  @override
  String get watchMarketChart => 'बाजार देखें 📈';

  @override
  String get gram => 'ग्राम';

  @override
  String get metalGold => 'सोना';

  @override
  String get metalSilver => 'चांदी';

  @override
  String get metalCopper => 'ताँबा';

  @override
  String get subscriptionPlans => 'सदस्यता योजनाएं';

  @override
  String get alarms => 'अलार्म';

  @override
  String get markets => 'बाजार';

  @override
  String get subscriptions => 'सदस्यताएँ';
}
