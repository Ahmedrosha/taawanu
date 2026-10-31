import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/logo_mark.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _run(Future<bool> Function(String locale, String fallbackName) signIn) async {
    if (_busy) return;
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await signIn(locale, t.defaultUserName);
      // لو الدخول نجح، التنقل للرئيسية بيحصل تلقائيًا من الـrouter.
    } catch (e) {
      debugPrint('Sign-in error: $e');
      messenger.showSnackBar(SnackBar(content: Text(t.signInFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewerLogin() async {
    final t = AppLocalizations.of(context);
    final email = TextEditingController();
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.reviewerSignIn),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t.email),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t.password),
              onSubmitted: (_) => Navigator.pop(context, true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t.signIn)),
        ],
      ),
    );
    final e = email.text;
    final pw = password.text;
    email.dispose();
    password.dispose();
    if (ok != true || e.trim().isEmpty || pw.isEmpty || !mounted) return;
    await _run((l, n) => AuthService.instance.signInWithEmail(email: e, password: pw, locale: l, fallbackName: n));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final auth = AuthService.instance;

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ضغطة طويلة على اللوجو بتفتح دخول المراجعين (لمراجعة Google Play وApp Store).
                    GestureDetector(
                      onLongPress: _busy ? null : _reviewerLogin,
                      child: const LogoMark.onDark(size: 112),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      t.appName,
                      style: GoogleFonts.reemKufi(
                        fontSize: 44,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        t.tagline,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFFDBEAFE)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(),
                    )
                  else ...[
                    _SignInButton(
                      label: t.signInWithGoogle,
                      icon: const _GoogleG(),
                      onPressed: () => _run((l, n) => auth.signInWithGoogle(locale: l, fallbackName: n)),
                    ),
                    if (auth.appleAvailable) ...[
                      const SizedBox(height: 12),
                      _SignInButton(
                        label: t.signInWithApple,
                        icon: const Icon(Icons.apple, color: Colors.white, size: 24),
                        dark: true,
                        onPressed: () => _run((l, n) => auth.signInWithApple(locale: l, fallbackName: n)),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignInButton extends StatelessWidget {
  const _SignInButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.dark = false,
  });

  final String label;
  final Widget icon;
  final VoidCallback onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: dark ? Colors.black : Colors.white,
          foregroundColor: dark ? Colors.white : AppColors.text,
          side: BorderSide(color: dark ? Colors.black : AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// حرف G بسيط بلون أزرق (من غير لوجو جوجل الرسمي الملون).
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: Text('G', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.blue, fontSize: 14)),
    );
  }
}
