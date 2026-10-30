import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/gen/app_localizations.dart';
import 'router.dart';
import 'services/prefs.dart';
import 'services/user_service.dart';
import 'theme/app_theme.dart';

/// اللغة الحالية للتطبيق (محفوظة على الجهاز). العربي هو الافتراضي.
final localeNotifier = ValueNotifier<Locale>(const Locale('ar'));

/// بيغير اللغة ويحفظها، وبيبلغ السيرفر عشان الإشعارات توصل بنفس اللغة.
Future<void> setAppLocale(Locale locale) async {
  localeNotifier.value = locale;
  await Prefs.instance.setLocale(locale);
  await UserService.instance.setLocale(locale.languageCode);
}

class TaawanuApp extends StatelessWidget {
  const TaawanuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        return MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: appRouter,
        );
      },
    );
  }
}
