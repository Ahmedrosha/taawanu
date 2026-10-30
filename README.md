# تعاونوا (Taawanu)

تطبيق لختمات القرآن الجماعية: ورد ثابت لكل عضو، وتدوير تلقائي كل دورة، ومجموعات خاصة بالدعوة أو عامة.

## التشغيل محليًا

```bash
flutter pub get
flutter gen-l10n
flutter run
```

## GitHub Actions

| الـ Workflow | بيشتغل إمتى | بيعمل إيه |
| --- | --- | --- |
| CI | مع كل push | `flutter analyze` والاختبارات |
| Bootstrap platforms | يدوي، مرة واحدة | بيولّد مجلدات `android` و `ios` ويعملهم commit |
| Build | يدوي | بيبني APK للأندرويد و/أو نسخة iOS من غير توقيع |

## الهيكل

```
lib/
  app.dart            التطبيق واللغة
  router.dart         التنقل (go_router)
  theme/              الألوان والثيم
  l10n/               النصوص بالعربي والإنجليزي
  features/           الشاشات حسب الميزة
  widgets/            عناصر مشتركة
```
