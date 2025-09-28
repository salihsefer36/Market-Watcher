// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get marketWatcher => '市场观察者';

  @override
  String get instantMarketAlarms => '即时市场提醒';

  @override
  String get continueWithGoogle => '使用 Google 继续';

  @override
  String get followedAlarms => '已关注的提醒';

  @override
  String get noAlarmsYet => '尚未设置提醒。';

  @override
  String get setAlarm => '设置提醒';

  @override
  String get watchMarkets => '关注市场';

  @override
  String get settings => '设置';

  @override
  String get general => '常规';

  @override
  String get applicationLanguage => '应用语言';

  @override
  String get notifications => '通知';

  @override
  String get forAllAlarms => '适用于所有提醒';

  @override
  String get account => '账户';

  @override
  String get signOut => '退出登录';

  @override
  String get language => '中文 (简体)';

  @override
  String get selectLanguage => '选择语言';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get save => '保存';

  @override
  String get symbol => '符号';

  @override
  String get name => '名称';

  @override
  String get price => '价格';

  @override
  String get noDataFound => '未找到数据';

  @override
  String get theAlarmHasNotBeenSetYet => '提醒尚未设置。';

  @override
  String get selectMarket => '选择市场';

  @override
  String get selectSymbol => '选择符号';

  @override
  String get selectChangePercent => '选择变化 %';

  @override
  String get editAlarm => '编辑提醒';

  @override
  String get watchMarket => '关注市场';

  @override
  String get signInWithGoogle => '使用 Google 登录';

  @override
  String get crypto => '加密货币';

  @override
  String get metals => '金属';

  @override
  String get noData => '无数据';

  @override
  String get pleaseSignInFirst => '请先登录';

  @override
  String get couldNotGetNotificationToken => '无法获取通知令牌，请重试。';

  @override
  String alarmAlreadyExists(Object displaySymbol, Object market) {
    return '$market 中已存在 $displaySymbol 的提醒';
  }

  @override
  String marketSymbolsCouldNotBeLoaded(Object market) {
    return '无法加载 $market 符号。';
  }

  @override
  String get noMarketDataFound => '未找到市场数据';

  @override
  String get watchMarketChart => '关注市场 📈';
}
