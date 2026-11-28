import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/groups_service.dart';
import '../theme/app_colors.dart';

/// علامة صغيرة تحت تقدم الورد: "هيتبعت لما النت يرجع"، طول ما فيه قراءة اتسجلت من غير نت ولسه ما اتبعتتش.
class PendingSyncNote extends StatelessWidget {
  const PendingSyncNote({super.key, required this.groupId, this.portionId});

  final String groupId;
  final String? portionId;

  @override
  Widget build(BuildContext context) {
    final svc = GroupsService.instance;
    return ValueListenableBuilder<int>(
      valueListenable: svc.pendingChanges,
      builder: (context, _, _) {
        if (!svc.hasPendingFor(groupId, portionId: portionId)) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_upload_outlined, size: 15, color: AppColors.statusInProgress),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                AppLocalizations.of(context).pendingSyncNote,
                style: TextStyle(fontSize: 12, color: AppColors.statusInProgress, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        );
      },
    );
  }
}
