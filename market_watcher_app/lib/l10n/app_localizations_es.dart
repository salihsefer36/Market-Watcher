// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get marketWatcher => 'Vigilante de Mercados';

  @override
  String get instantMarketAlarms => 'Alertas de mercado instantáneas';

  @override
  String get continueWithGoogle => 'Continuar con Google';

  @override
  String get followedAlarms => 'Alertas seguidas';

  @override
  String get noAlarmsYet => 'Todavía no se han configurado alertas.';

  @override
  String get setAlarm => 'Fijar';

  @override
  String get watchMarkets => 'Observar mercados';

  @override
  String get settings => 'Configuración';

  @override
  String get general => 'General';

  @override
  String get applicationLanguage => 'Idioma de la aplicación';

  @override
  String get notifications => 'Notificaciones';

  @override
  String get forAllAlarms => 'Para todas las alertas';

  @override
  String get account => 'Cuenta';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get language => 'Español';

  @override
  String get selectLanguage => 'Seleccionar idioma';

  @override
  String get cancel => 'Cancelar';

  @override
  String get delete => 'Eliminar';

  @override
  String get edit => 'Editar';

  @override
  String get save => 'Guardar';

  @override
  String get symbol => 'Símbolo';

  @override
  String get name => 'Nombre';

  @override
  String get price => 'Precio';

  @override
  String get noDataFound => 'No se encontraron datos';

  @override
  String get theAlarmHasNotBeenSetYet =>
      'La alerta aún no ha sido configurada.';

  @override
  String get selectMarket => 'Seleccionar mercado';

  @override
  String get selectSymbol => 'Seleccionar símbolo';

  @override
  String get selectChangePercent => 'Seleccionar cambio %';

  @override
  String get editAlarm => 'Editar alerta';

  @override
  String get watchMarket => 'Observar mercado';

  @override
  String get signInWithGoogle => 'Iniciar sesión con Google';

  @override
  String get crypto => 'CRYPTO';

  @override
  String get metals => 'METALES';

  @override
  String get noData => 'Sin datos';

  @override
  String get pleaseSignInFirst => 'Por favor inicie sesión primero';

  @override
  String get couldNotGetNotificationToken =>
      'No se pudo obtener el token de notificación. Inténtelo de nuevo.';

  @override
  String alarmAlreadyExists(Object displaySymbol, Object market) {
    return 'Ya existe una alerta para $displaySymbol en $market';
  }

  @override
  String marketSymbolsCouldNotBeLoaded(Object market) {
    return 'No se pudieron cargar los símbolos de $market.';
  }

  @override
  String get noMarketDataFound => 'No se encontraron datos de mercado';

  @override
  String get watchMarketChart => 'Observar mercado 📈';

  @override
  String get gram => 'Gramo';

  @override
  String get metalGold => 'Oro';

  @override
  String get metalSilver => 'Plata';

  @override
  String get metalCopper => 'Cobre';

  @override
  String get subscriptionPlans => 'Planes de suscripción';

  @override
  String get alarms => 'Alarmas';

  @override
  String get markets => 'Mercados';

  @override
  String get subscriptions => 'Suscripciones';

  @override
  String get bestOffer => 'Mejor Oferta';

  @override
  String get free => 'Gratis';

  @override
  String get featureCheck10Min => 'Intervalo de 10 min';

  @override
  String get feature5Alarms => 'Límite de 5 alarmas';

  @override
  String get featureCheck3Min => 'Intervalo de 3 min';

  @override
  String get feature20Alarms => 'Límite de 20 alarmas';

  @override
  String get featureNoAds => 'Sin anuncios';

  @override
  String get featureCheck1Min => 'Intervalo de 1 min';

  @override
  String get featureUnlimitedAlarms => 'Alarmas ilimitadas';

  @override
  String get featurePrioritySupport => 'Soporte prioritario';

  @override
  String get currentPlan => 'Plan Actual';

  @override
  String get upgrade => 'Actualizar';

  @override
  String get downgrade => 'Bajar de plan';

  @override
  String get anErrorOccurred =>
      'Ocurrió un error. Por favor, inténtalo de nuevo.';
}
