import 'features/update/update_widgets.dart';
import 'services/update_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/gen/app_localizations.dart';
import 'router.dart';
import 'services/prefs.dart';
import 'services/user_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

/// اللغة الحالية للتطبيق (محفوظة على الجهاز). العربي هو الافتراضي.
final localeNotifier = ValueNotifier<Locale>(const Locale('ar'));

/// بيغير اللغة ويحفظها، وبيبلغ السيرفر عشان الإشعارات توصل بنفس اللغة.
Future<void> setAppLocale(Locale locale) async {
  localeNotifier.value = locale;
  await Prefs.instance.setLocale(locale);
  await UserService.instance.setLocale(locale.languageCode);
}

/// المظهر: تلقائي (زي الموبايل) أو فاتح أو غامق. محفوظ على الجهاز.
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> setAppThemeMode(ThemeMode mode) async {
  themeModeNotifier.value = mode;
  await Prefs.instance.setThemeMode(mode.name);
}

class TaawanuApp extends StatelessWidget {
  const TaawanuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([localeNotifier, themeModeNotifier]),
      builder: (context, _) {
        final locale = localeNotifier.value;
        final mode = themeModeNotifier.value;
        return MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          // الألوان في الشاشات بتتقري من AppColors، فلما الوضع يتغير بنعيد بناء كل حاجة.
          builder: (context, child) {
            final dark = mode == ThemeMode.dark ||
                (mode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
            final b = dark ? Brightness.dark : Brightness.light;
            AppColors.use(b);
            var app = child ?? const SizedBox.shrink();
            // أندرويد: شريط النظام اللي تحت كان بيغطي آخر الشاشة في كل الصفحات، فبنسيب مكانه.
            if (defaultTargetPlatform == TargetPlatform.android) {
              app = ColoredBox(
                color: AppColors.background,
                child: SafeArea(top: false, left: false, right: false, child: app),
              );
            }
            // نسخة أقدم من أقل نسخة مسموحة: شاشة "لازم تحدّث" مكان التطبيق.
            final inner = app;
            app = ValueListenableBuilder<UpdateNeed>(
              valueListenable: UpdateService.instance.need,
              builder: (context, need, _) => need == UpdateNeed.required ? const UpdateRequiredScreen() : inner,
            );
            return KeyedSubtree(key: ValueKey(b), child: app);
          },
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
