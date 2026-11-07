import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/update_service.dart';
import '../../theme/app_colors.dart';

/// شاشة كاملة لما النسخة أقدم من أقل نسخة مسموحة: لازم يحدّث عشان يكمل.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Material(
      color: AppColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.system_update, size: 64, color: AppColors.accent),
              const SizedBox(height: 20),
              Text(t.updateRequiredTitle,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(t.updateRequiredBody, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 28),
              FilledButton(onPressed: UpdateService.instance.update, child: Text(t.updateNow)),
            ],
          ),
        ),
      ),
    );
  }
}

/// كارت "فيه تحديث جديد" في الرئيسية. بيتقفل ويرجع بعد يوم.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final svc = UpdateService.instance;
    return ValueListenableBuilder<UpdateNeed>(
      valueListenable: svc.need,
      builder: (context, need, _) {
        if (need != UpdateNeed.optional || svc.bannerDismissed) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Material(
            color: AppColors.goldTint,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 8),
              child: Row(
                children: [
                  Icon(Icons.system_update, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.updateAvailableTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(t.updateAvailableBody(svc.latest), style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                    onPressed: svc.update,
                    child: Text(t.updateNow),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: svc.dismissBanner,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
