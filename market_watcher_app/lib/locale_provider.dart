import 'package:flutter/material.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('en'); // Varsayılan dil

  Locale get locale => _locale;

  void setLocale(String languageCode) {
    _locale = Locale(languageCode);
    notifyListeners();
  }
}