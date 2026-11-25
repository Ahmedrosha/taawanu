import 'features/update/update_widgets.dart';
import 'services/update_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/ar_digits.dart';
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

/// للرسايل اللي بتظهر من برا الشاشات (زي إرسال قراءة اتسجلت من غير نت).
final rootMessenger = GlobalKey<ScaffoldMessengerState>();

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
          // الألوان في الشاشات بتتقري من AppColors، فلما الوضع يتغير بنعيد رسم كل حاجة (من غير ما الشاشات تتبني من الأول).
          builder: (context, child) {
            final dark = mode == ThemeMode.dark ||
                (mode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
            return _ThemeRefresh(
              brightness: dark ? Brightness.dark : Brightness.light,
              builder: () {
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
                return ValueListenableBuilder<UpdateNeed>(
                  valueListenable: UpdateService.instance.need,
                  builder: (context, need, _) => need == UpdateNeed.required ? const UpdateRequiredScreen() : inner,
                );
              },
            );
          },
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            // العربي بأرقام عربي في كل الجمل.
            LocalizedDigitsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: appRouter,
          scaffoldMessengerKey: rootMessenger,
        );
      },
    );
  }
}

/// بيطبّق ألوان الوضع (فاتح/داكن) على AppColors ويعيد رسم كل الشاشات.
/// قبل كده كان بيعيد بناء التطبيق كله من الأول، ولما الوضع يتغير من إعدادات الموبايل والتطبيق في الخلفية
/// (أيفون بيعمل كده وهو بياخد صورة للتطبيق) كانت بتظهر شاشة رمادي. دلوقتي: نستنى لما التطبيق يرجع قدام،
/// ونعلّم كل الشاشات إنها تترسم تاني بنفس حالتها.
class _ThemeRefresh extends StatefulWidget {
  const _ThemeRefresh({required this.brightness, required this.builder});

  final Brightness brightness;
  final Widget Function() builder;

  @override
  State<_ThemeRefresh> createState() => _ThemeRefreshState();
}

class _ThemeRefreshState extends State<_ThemeRefresh> with WidgetsBindingObserver {
  late Brightness _applied = widget.brightness;

  @override
  void initState() {
    super.initState();
    AppColors.use(_applied);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _foreground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  @override
  void didUpdateWidget(_ThemeRefresh old) {
    super.didUpdateWidget(old);
    if (widget.brightness != _applied && _foreground) _apply();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.brightness != _applied) setState(_apply);
  }

  void _apply() {
    _applied = widget.brightness;
    AppColors.use(_applied);
    // كل الشاشات اللي تحت بتقرا AppColors وهي بتترسم: نعلّمها كلها تترسم تاني بعد الفريم ده.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void mark(Element e) {
        e.markNeedsBuild();
        e.visitChildren(mark);
      }

      (context as Element).visitChildren(mark);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder();
}
